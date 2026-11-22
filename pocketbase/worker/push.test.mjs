// node --test pocketbase/worker/push.test.mjs
import assert from 'node:assert/strict';
import { createVerify, generateKeyPairSync } from 'node:crypto';
import { test } from 'node:test';
import { createAuth, createPush, jwtFor, messageFor, readRequest, sendTopic, serve } from './push.mjs';

const { privateKey, publicKey } = generateKeyPairSync('rsa', { modulusLength: 2048 });
const sa = {
  project_id: 'cascapp-teste',
  client_email: 'push@cascapp-teste.iam.gserviceaccount.com',
  token_uri: 'https://oauth2.googleapis.com/token',
  private_key: privateKey.export({ type: 'pkcs8', format: 'pem' }),
};

/** `fetch` de mentira: anota cada pedido e responde o que `answer` mandar. */
function fakeFetch(answer) {
  const calls = [];
  const fn = async (url, init) => {
    calls.push({ url, init });
    const { status = 200, body = {} } = answer(url, init) ?? {};
    return {
      ok: status >= 200 && status < 300,
      status,
      json: async () => body,
      text: async () => JSON.stringify(body),
    };
  };
  fn.calls = calls;
  return fn;
}

test('JWT: assinado com a chave da conta, para o escopo do FCM, por 1 h', () => {
  const jwt = jwtFor(sa, 1000);
  const [header, claims, signature] = jwt.split('.');
  assert.deepEqual(JSON.parse(Buffer.from(header, 'base64url')), { alg: 'RS256', typ: 'JWT' });
  const body = JSON.parse(Buffer.from(claims, 'base64url'));
  assert.equal(body.iss, sa.client_email);
  assert.equal(body.aud, sa.token_uri);
  assert.equal(body.scope, 'https://www.googleapis.com/auth/firebase.messaging');
  assert.equal(body.exp - body.iat, 3600);
  assert.ok(createVerify('RSA-SHA256').update(`${header}.${claims}`).verify(publicKey, signature, 'base64url'));
});

test('token OAuth: pedido uma vez e reaproveitado até perto de vencer', async () => {
  let clock = 0;
  const fetchImpl = fakeFetch(() => ({ body: { access_token: `t${clock}`, expires_in: 3600 } }));
  const auth = createAuth(sa, fetchImpl, () => clock);
  assert.equal(await auth(), 't0');
  clock = 3000 * 1000;
  assert.equal(await auth(), 't0', 'antes de vencer, o mesmo');
  assert.equal(fetchImpl.calls.length, 1);
  assert.match(fetchImpl.calls[0].init.body, /grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer/);
  clock = 3541 * 1000;
  assert.equal(await auth(), `t${clock}`, 'a 1 min de vencer, troca');
});

test('mensagem data, com prioridade alta', () => {
  assert.deepEqual(messageFor('tok', { title: 'Ana', body: 'oi', friend: 'abc' }), {
    message: { token: 'tok', data: { title: 'Ana', body: 'oi', friend: 'abc' }, android: { priority: 'HIGH' } },
  });
});

test('pedido do PocketBase: só tokens de verdade e textos cortados', () => {
  assert.equal(readRequest({ tokens: [], title: 'a', body: 'b', friend: 'c' }, 20), null);
  assert.equal(readRequest({ tokens: ['x'], title: 1, body: 'b', friend: 'c' }, 20), null);
  assert.equal(readRequest({ tokens: Array(21).fill('x'), title: 'a', body: 'b', friend: 'c' }, 20), null);
  const ok = readRequest({ tokens: ['x', 3, ''], title: 'a'.repeat(200), body: 'b', friend: 'c' }, 20);
  assert.deepEqual(ok.tokens, ['x']);
  assert.equal(ok.title.length, 80);
});

test('manda para cada aparelho e devolve os tokens que o FCM esqueceu', async () => {
  const fetchImpl = fakeFetch((url, init) => {
    const token = JSON.parse(init.body).message.token;
    if (token === 'velho') return { status: 404, body: { error: { status: 'NOT_FOUND', details: [{ errorCode: 'UNREGISTERED' }] } } };
    if (token === 'ruim') return { status: 500, body: {} };
    return { status: 200, body: { name: 'ok' } };
  });
  const push = createPush({ sa, fetchImpl, auth: async () => 'bearer1', fcmBase: 'https://fcm.local' });
  const out = await push({ tokens: ['bom', 'velho', 'ruim'], title: 'Ana', body: 'oi', friend: 'abc' });
  assert.deepEqual(out, { sent: 1, dropped: ['velho'] });
  assert.equal(fetchImpl.calls[0].url, 'https://fcm.local/v1/projects/cascapp-teste/messages:send');
  assert.equal(fetchImpl.calls[0].init.headers.Authorization, 'Bearer bearer1');
});

test('tópico: a versão nova vai para todos os inscritos', async () => {
  const fetchImpl = fakeFetch(() => ({ status: 200, body: { name: 'ok' } }));
  await sendTopic({ sa, fetchImpl, auth: async () => 'b', fcmBase: 'https://fcm.local' }, 'updates', { type: 'update', version: '1.60' });
  assert.deepEqual(JSON.parse(fetchImpl.calls[0].init.body), {
    message: { topic: 'updates', data: { type: 'update', version: '1.60' }, android: { priority: 'HIGH' } },
  });
  const refused = fakeFetch(() => ({ status: 403, body: {} }));
  await assert.rejects(sendTopic({ sa, fetchImpl: refused, auth: async () => 'b', fcmBase: 'x' }, 'updates', {}), /FCM recusou: 403/);
});

test('servidor: só com segredo, e responde o que o push devolveu', async (t) => {
  const seen = [];
  const server = serve(async (request) => {
    seen.push(request);
    return { sent: request.tokens.length, dropped: [] };
  }, { port: 0, secret: 's3gredo', maxTokens: 20 });
  await new Promise((resolve) => server.once('listening', resolve));
  t.after(() => server.close());
  const url = `http://127.0.0.1:${server.address().port}/send`;
  const body = JSON.stringify({ tokens: ['a'], title: 'Ana', body: 'oi', friend: 'abc' });
  const post = (headers, data = body) => fetch(url, { method: 'POST', headers, body: data });

  assert.equal((await post({})).status, 403, 'sem segredo');
  assert.equal((await post({ 'x-push-secret': 'errado' })).status, 403, 'segredo errado');
  assert.equal((await post({ 'x-push-secret': 's3gredo' }, '{')).status, 400, 'JSON quebrado');
  const ok = await post({ 'x-push-secret': 's3gredo' });
  assert.equal(ok.status, 200);
  assert.deepEqual(await ok.json(), { sent: 1, dropped: [] });
  assert.equal(seen.length, 1);
});
