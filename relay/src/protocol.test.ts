import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import { cleanName, MAX_NAME_LENGTH, parseClientMessage } from './protocol.js';

/**
 * A limpeza do apelido, que é a única string deste serviço que sai do teclado de
 * uma pessoa e vai para a tela de outra.
 *
 * O cliente também limpa a dele, e isso não conta: quem manda o campo é um
 * socket qualquer.
 */
describe('cleanName', () => {
  it('remove o que não se desenha e corta no limite', () => {
    assert.equal(cleanName('Lucas'), 'Lucas');
    assert.equal(cleanName('  Ana  '), 'Ana', 'espaço nas pontas sai');
    // A quebra de linha é o caso que estraga a lista: ela estica o cartão para
    // fora do desenho, e nada acusa — o texto simplesmente some do enquadramento.
    assert.equal(cleanName('Beto\nfalso'), 'Betofalso');
    assert.equal(cleanName('Beto\tfalso\r\n'), 'Betofalso');
    // Montado com `fromCharCode` em vez de escrito: um NUL literal no fonte
    // torna o arquivo binário para metade das ferramentas que o leem.
    const nul = String.fromCharCode(0);
    const del = String.fromCharCode(127);
    assert.equal(cleanName(`a${nul}b${del}`), 'ab', 'nulo e DEL também');
    assert.equal(
      cleanName('Um nome absurdamente comprido').length,
      MAX_NAME_LENGTH,
      'o comprido é cortado no limite do cartão'
    );
    // Acento e emoji ficam: o limite é de layout, não de alfabeto, e cortar
    // "José" seria decidir que nome é nome.
    assert.equal(cleanName('José 🎲'), 'José 🎲');
  });

  it('trata como vazio tudo que não é texto', () => {
    assert.equal(cleanName(undefined), '');
    assert.equal(cleanName(null), '');
    assert.equal(cleanName(42), '');
    assert.equal(cleanName({ toString: () => 'esperto' }), '');
  });
});

describe('parseClientMessage host', () => {
  it('aceita o cliente antigo, que não conhece o campo', () => {
    // Ele abre partida privada e sem apelido — que é exatamente o que ele
    // sempre quis dizer, e o que este relay sempre entendeu.
    const message = parseClientMessage(JSON.stringify({ t: 'host', room: 'ABC123' }));
    assert.deepEqual(message, {
      t: 'host',
      room: 'ABC123',
      game: '',
      listed: false,
      tc: 0,
      seats: 2,
      name: '',
    });
  });

  it('limpa o apelido na fronteira, e não na hora de listar', () => {
    // Assim não existe nenhum instante do processo em que o nome sujo está
    // guardado em memória — a limpeza é uma coisa que acontece uma vez, e não
    // uma coisa de que cada leitor precisa lembrar.
    const message = parseClientMessage(
      JSON.stringify({ t: 'host', room: 'ABC123', name: 'Ana\nSilva' })
    );
    assert.equal(message?.t === 'host' && message.name, 'AnaSilva');
  });
});
