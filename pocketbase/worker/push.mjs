// Notificação no celular pelo Firebase Cloud Messaging (FCM HTTP v1), para a
// mensagem de amigo que chega com o app fechado.
//
// Quem chama é só o PocketBase (`pb_hooks/conversa.pb.js`, depois de gravar a
// mensagem), pela rede do compose e com segredo (`PUSH_SECRET`). Ele manda os
// tokens dos aparelhos de quem recebe, o título e o texto; aqui se assina o
// JWT da conta de serviço, troca-se por um token OAuth (guardado até perto de
// vencer) e manda-se uma mensagem `data` por aparelho. É `data`, e não
// `notification`, para o app decidir: aberto, ele não mostra nada (a bolinha
// basta); fechado, o `PushService` do plugin Android desenha a notificação.
//
// Serviço à parte porque o PocketBase não assina RS256. A chave da conta de
// serviço mora só na Pi (`FIREBASE_SA`, um arquivo montado só aqui), nunca no
// repositório.
//
// Mesma imagem do worker, outro processo: `node push.mjs`.

import { createSign } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { createServer } from 'node:http';
import { pathToFileURL } from 'node:url';

const env = (name, fallback) => process.env[name] ?? fallback;

export const config = {
  port: Number(env('PORT', '8095')),
  secret: env('PUSH_SECRET', ''),
  saFile: env('FIREBASE_SA', '/run/secrets/firebase-sa.json'),
  fcmBase: env('FCM_BASE', 'https://fcm.googleapis.com').replace(/\/+$/, ''),
  maxTokens: 20,
};

const SCOPE = 'https://www.googleapis.com/auth/firebase.messaging';
const base64url = (data) => Buffer.from(data).toString('base64url');

/** O JWT da conta de serviço, assinado com a chave dela, válido por 1 h. */
export function jwtFor(sa, nowSeconds) {
  const header = base64url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
  const claims = base64url(JSON.stringify({
    iss: sa.client_email, scope: SCOPE, aud: sa.token_uri, iat: nowSeconds, exp: nowSeconds + 3600,
  }));
  const signature = createSign('RSA-SHA256').update(`${header}.${claims}`).sign(sa.private_key, 'base64url');
  return `${header}.${claims}.${signature}`;
}

/** Um token OAuth de cada vez, trocado 1 min antes de vencer. */
export function createAuth(sa, fetchImpl = fetch, now = () => Date.now()) {
  let cached = null;
  return async () => {
    if (cached && now() < cached.until) return cached.token;
    const reply = await fetchImpl(sa.token_uri, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
        assertion: jwtFor(sa, Math.floor(now() / 1000)),
      }).toString(),
    });
    if (!reply.ok) throw new Error(`token OAuth recusado: ${reply.status}`);
    const data = await reply.json();
    cached = { token: data.access_token, until: now() + (Number(data.expires_in ?? 3600) - 60) * 1000 };
    return cached.token;
  };
}

/** A mensagem `data` do FCM v1 para um aparelho. Prioridade alta acorda o celular. */
export function messageFor(token, { title, body, friend }) {
  return { message: { token, data: { title, body, friend }, android: { priority: 'HIGH' } } };
}

/** O pedido do PocketBase, limpo, ou `null` se não vale. */
export function readRequest(body, maxTokens) {
  const tokens = Array.isArray(body?.tokens) ? body.tokens.filter((t) => typeof t === 'string' && t.length > 0 && t.length <= 500) : [];
  if (tokens.length === 0 || tokens.length > maxTokens) return null;
  if (typeof body.title !== 'string' || typeof body.body !== 'string' || typeof body.friend !== 'string') return null;
  return { tokens, title: body.title.slice(0, 80), body: body.body.slice(0, 200), friend: body.friend.slice(0, 40) };
}

/**
 * Manda para cada token. Devolve `{sent, dropped}`: `dropped` são os tokens que
 * o FCM diz que não existem mais (app desinstalado, token trocado), para o
 * PocketBase apagar.
 */
export function createPush({ sa, fetchImpl = fetch, auth, fcmBase }) {
  const url = `${fcmBase}/v1/projects/${sa.project_id}/messages:send`;
  return async ({ tokens, title, body, friend }) => {
    const bearer = await auth();
    let sent = 0;
    const dropped = [];
    for (const token of tokens) {
      const reply = await fetchImpl(url, {
        method: 'POST',
        headers: { Authorization: `Bearer ${bearer}`, 'Content-Type': 'application/json' },
        body: JSON.stringify(messageFor(token, { title, body, friend })),
      });
      if (reply.ok) {
        sent += 1;
        continue;
      }
      const text = await reply.text();
      if (reply.status === 404 || text.includes('UNREGISTERED') || text.includes('registration token is not a valid')) {
        dropped.push(token);
      } else {
        console.log(`FCM ${reply.status}`);
      }
    }
    return { sent, dropped };
  };
}

/**
 * Uma mensagem `data` para todos os aparelhos inscritos em `topic`. É o aviso
 * de versão nova: a esteira de release chama na linha de comando, e o
 * `PushService` do app mostra a mesma notificação da consulta em segundo plano.
 */
export async function sendTopic({ sa, fetchImpl = fetch, auth, fcmBase }, topic, data) {
  const reply = await fetchImpl(`${fcmBase}/v1/projects/${sa.project_id}/messages:send`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${await auth()}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ message: { topic, data, android: { priority: 'HIGH' } } }),
  });
  if (!reply.ok) throw new Error(`FCM recusou: ${reply.status} ${await reply.text()}`);
}

export function serve(push, { port, secret, maxTokens }) {
  return createServer((req, res) => {
    const reply = (status, body) => {
      res.writeHead(status, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify(body));
    };
    if (req.method !== 'POST' || req.url !== '/send') return reply(404, { error: 'não existe' });
    if (!secret || req.headers['x-push-secret'] !== secret) return reply(403, { error: 'segredo' });
    let text = '';
    req.setEncoding('utf8');
    req.on('data', (chunk) => {
      text += chunk;
      if (text.length > 32768) {
        reply(413, { error: 'grande demais' });
        req.destroy();
      }
    });
    req.on('end', async () => {
      if (res.writableEnded) return;
      let request;
      try {
        request = readRequest(JSON.parse(text), maxTokens);
      } catch {
        request = null;
      }
      if (!request) return reply(400, { error: 'pedido inválido' });
      try {
        const out = await push(request);
        reply(200, out);
        console.log(`push ${out.sent}/${request.tokens.length}`);
      } catch (error) {
        console.log(`push falhou: ${error.message}`);
        reply(502, { error: 'FCM fora' });
      }
    });
  }).listen(port, '0.0.0.0');
}

if (import.meta.url === pathToFileURL(process.argv[1]).href && process.argv[2] === 'topic') {
  // Da esteira de release: `FIREBASE_SA=sa.json node push.mjs topic updates type=update version=1.60`.
  const sa = JSON.parse(readFileSync(config.saFile, 'utf8'));
  const data = Object.fromEntries(process.argv.slice(4).map((pair) => pair.split(/=(.*)/s).slice(0, 2)));
  await sendTopic({ sa, auth: createAuth(sa), fcmBase: config.fcmBase }, process.argv[3], data);
  console.log(`tópico ${process.argv[3]}: ${JSON.stringify(data)}`);
} else if (import.meta.url === pathToFileURL(process.argv[1]).href) {
  const sa = JSON.parse(readFileSync(config.saFile, 'utf8'));
  const push = createPush({ sa, auth: createAuth(sa), fcmBase: config.fcmBase });
  serve(push, config);
  console.log(`push em :${config.port}, projeto ${sa.project_id}`);
}
