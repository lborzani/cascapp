# Plano: missões, itens exclusivos e presentes

**Origem:** descrito no chat (2026-11-24)
**Objetivo:** dar ao jogador missões que pagam moedas e itens exclusivos (que não se compram), deixar o
alicerce para eventos com missões próprias e permitir presentear amigos (item da loja ou presentinho
diário de moedas).
**Admin:** o painel do PocketBase (`/_/`, só na tailnet) é o admin. Preços, itens exclusivos, eventos
e missões viram coleções editáveis lá, e o servidor lê dali, não mais de constantes.
**Fora de escopo:** tela de admin própria, missões com amigo ou só online, mandar moedas
livremente, push de missão concluída, arte nova (as exclusivas usam os encaixes desenhados por código).

**Suposições (confirmar):**
- **Três trilhas, uma estrutura.** Uma missão pertence a um período: `daily` (3 sorteadas por dia, só
  moedas), `perm` (conquistas permanentes, ex. "vença 50 partidas de sinuca", que pagam item exclusivo)
  ou `event:<id>` (vale entre `starts` e `ends`, missões e itens próprios do evento).
- **Eventos, missões e preços são dados**, editados no admin, sem deploy. O app só desenha o que o
  servidor manda.
- **Limite do admin:** ele preça, tranca e distribui itens que o app já conhece (`Cosmetics.ITEMS`).
  Item com visual novo (arte, desenho) ainda exige uma versão do app. Exceção barata, se você quiser:
  títulos (só texto) definidos inteiros no admin.
- **O progresso conta a partir do deploy**, sem histórico retroativo.
- **Os exclusivos usam os encaixes desenhados por código** (moldura, capa, título, cor do nome).
  Ficam numa lista `EXCLUSIVE` no servidor: não se compram e só se equipam se você tiver o item.
- **O presente de item** paga o preço da loja; o item entra na conta do amigo na hora e o presente fica
  "fechado" até ele abrir. Exclusivo não se presenteia.
- **O presentinho diário** é de 10 moedas, um por amigo por dia, e cada um recebe no máximo 5 por dia.
  A partir daí o envio é recusado.

**Como rodar as verificações:**
- `node --test pocketbase/*.test.js`
- `pocketbase serve --http 127.0.0.1:18091 --dir /tmp/pb --migrationsDir pocketbase/pb_migrations --hooksDir pocketbase/pb_hooks`
- `CASCAPP_PB_URL=http://127.0.0.1:18091 godot --headless --path . res://tests/<probe>.tscn`
- `godot --headless --path . --script res://tests/test_runner.gd`

## Status
Concluído em 2026-11-24 (todas as fases verificadas)

---

## Fase 1: catálogo no admin (preços e exclusivos em coleção)
**Meta:** editar o preço de um item no admin muda a loja, sem deploy.
**Mudanças:** coleção `shop_items` `{item, price, exclusive, active}` com uma migration que semeia os
`PRICES` de hoje; `loja.js` lê a coleção (`/shop`, `/buy`, `lookProblem`) em vez da constante. Leitura
pública só dos ativos e não exclusivos; escrita só por superusuário.

**Critérios de aceite:**
- [x] Depois da migration, `/api/cascapp/shop` devolve exatamente os mesmos preços de hoje
- [x] Mudar o preço no admin → o `/shop` e o `/buy` usam o novo na hora
- [x] `active = false` some da loja e o `/buy` recusa, mas quem já tem continua equipando
- [x] `exclusive = true`: fora do `/shop`, `/buy` recusa, só equipa quem tem
- [x] O app não consegue escrever em `shop_items`

**Testes:**
- [x] [auto] `node --test pocketbase/loja.test.js` (regras puras recebendo o catálogo como argumento)
- [x] [auto] `shop_probe` verde, mais os casos de inativo e exclusivo
- [x] [manual] mudar um preço no admin local e ver a loja do app refletir

## Fase 2: missões e eventos no servidor
**Meta:** o servidor conta o progresso e paga as missões das três trilhas.
**Mudanças:** coleções `events` `{key, name, starts, ends}` e `missions` `{key, track: daily|perm|event,
event, kind: play|win|variety, game (opcional), title, target, reward_coins, reward_item, active}`, editadas no
admin, com uma migration que semeia as diárias e algumas conquistas. `pb_hooks/missoes.js` (regras puras:
sorteio diário por hash, progresso, janela do evento, poda dos períodos vencidos), `pb_hooks/missoes.pb.js` (`GET /api/cascapp/missions` e
`POST /api/cascapp/missions/claim {key}`), o `/reward` também avança as missões na mesma transação,
migration com o campo `missions_state` em `users` (JSON, protegido no
`updateRule`).

**Critérios de aceite:**
- [x] O sorteio diário é estável no dia, muda no dia seguinte e é diferente entre contas
- [x] Uma partida reportada avança as missões que casam (jogar, vencer, jogo X, jogos variados)
- [x] Resgatar uma missão incompleta, já resgatada ou de evento fora da data → erro; uma completa → paga uma vez só
- [x] Criar um evento e uma missão no admin → aparecem no `GET /missions` dentro da janela e somem fora dela
- [x] `reward_item` precisa existir em `shop_items` (validado no hook ao salvar pelo admin)
- [x] O campo `missions_state` não se escreve pelo update da conta

**Testes:**
- [x] [auto] `node --test pocketbase/missoes.test.js` (sorteio, progresso, janela do evento, poda)
- [x] [auto] `tests/missions_probe.tscn` contra o PB local (rotas, transação, `updateRule`, exclusivo)
- [x] [auto] `node --test pocketbase/loja.test.js` e `shop_probe` continuam verdes

**Portão:** tudo verde e o seu ok.

## Fase 3: missões no app
**Meta:** ver e resgatar as missões; os exclusivos aparecem na loja.
**Mudanças:** `Account.fetch_missions()`/`claim_mission()`, um painel de Missões aberto pela aba Você
(abas Hoje / Conquistas / Evento, esta só quando há evento ativo), uma marca "missão concluída" no
cartão de resultado quando o `/reward` avisar, os exclusivos em `Cosmetics.ITEMS` e a loja mostrando o
exclusivo trancado ("só por missão").

**Critérios de aceite:**
- [x] O painel lista as missões com barra de progresso e botão Resgatar quando estão completas
- [x] Resgatar atualiza o saldo e o `owned` sem reabrir o painel
- [x] Exclusivo não ganho aparece trancado na loja; ganho, dá para equipar

**Testes:**
- [x] [auto] `test_runner.gd` e `screen_sheet` sem erro de script
- [x] [manual] jogar 1 partida contra o bot → missão avança; resgatar → moedas entram
- [x] [manual] painel e loja no celular (layout e tema escuro)

## Fase 4: presentes no servidor
**Meta:** mandar um item ou o presentinho diário a um amigo, e abrir o que chegou.
**Mudanças:** migration da coleção `gifts` `{from, to, item, coins, opened, created}` (só leitura para
o dono, escrita só pelos hooks), `pb_hooks/presentes.pb.js`: `POST /gifts {to, item}`,
`POST /gifts/daily {to}`, `GET /gifts`, `POST /gifts/{id}/open`. Push pelo `notify` que já existe em
`conversa.js`.

**Critérios de aceite:**
- [x] Só entre amigos aceitos; não dá para presentear a si mesmo
- [x] Item: cobra o preço, recusa se o amigo já tem ou se o item é exclusivo; entra no `owned` dele
- [x] Diário: 1 por par por dia; o sexto do dia que chega ao mesmo destinatário é recusado
- [x] Abrir marca o presente como aberto; abrir o de outra pessoa → 404

**Testes:**
- [x] [auto] `node --test pocketbase/presentes.test.js` (limites, datas)
- [x] [auto] `tests/gifts_probe.tscn` com duas contas amigas contra o PB local

## Fase 5: presentes no app
**Meta:** presentear e abrir presentes pelo app.
**Mudanças:** um botão "Presentear" no cartão do item da loja (escolhe o amigo), "Presentinho" no perfil do
amigo, a caixa de presentes na aba Você (linha acesa com o número de fechados), um aviso no menu quando chega
presente, e a caixa que balança e solta confete ao abrir.

**Critérios de aceite:**
- [x] Presentear um item da loja a um amigo → saldo desce e o amigo vê o presente fechado
- [x] Abrir → animação, e o item fica equipável
- [x] O indicador some quando não há presentes fechados

**Testes:**
- [x] [auto] `test_runner.gd` sem erro
- [x] [manual] dois aparelhos (ou conta + emulador): mandar, receber o push, abrir

## Fase 6: fechamento ✅
Novidades da 1.69 no `CHANGELOG.md`, seção "Loja e visual" do `README.md`, `pocketbase/README.md`
(missões, eventos e presentes) e runbook no vault: "Runbook - Loja, missões e eventos no admin do cascapp".
