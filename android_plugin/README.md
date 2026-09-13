# Plugins Android (opcionais)

O jogo funciona sem nada disto: o QR é **gerado** em GDScript puro e o convidado
pode entrar digitando o código de 6 caracteres. Estes dois plugins habilitam os
dois caminhos que exigem código nativo:

| Plugin | Singleton | Habilita |
| --- | --- | --- |
| `GodotNfcPlugin.kt` + `NfcHceService.kt` | `GodotNfc` | encostar os celulares para parear |
| `GodotQrScannerPlugin.kt` | `GodotQrScanner` | ler o QR com a câmera, dentro da própria tela do jogo |
| `GodotWifiLinkPlugin.kt` | `GodotWifiLink` | hotspot local (caminho legado, ver README raiz) |

## NFC: quando o toque vibra e nada acontece

A vibração é o sistema anunciando que **houve contato de rádio** — ela não diz
nada sobre o que veio depois. Entre o contato e a partida abrir há quatro
degraus, e antes cada um deles falhava do mesmo jeito: em silêncio.

1. **O SELECT foi para outro app.** Declarar o AID no manifesto não garante
   roteamento: outro app pode declarar o mesmo, e alguns fabricantes exigem
   habilitar o serviço nas configurações de NFC. `startBroadcast` agora consulta
   `CardEmulation.isDefaultServiceForAid` e avisa quando não é o padrão.
2. **O anfitrião não estava anunciando.** O HCE responde `6A82` quando o payload
   é nulo — o app está aberto, mas ninguém abriu "Criar partida". Antes isso
   virava "Resposta NFC inesperada"; agora diz o que fazer.
3. **O anfitrião se apresentava como NFC-B.** O leitor pedia só `FLAG_READER_NFC_A`
   e ignorava o resto. Agora pede os dois.
4. **O payload chegou e o GDScript descartou.** `_join()` voltava sem dizer nada
   quando já havia uma tentativa em curso.

`NfcHceService.describeFailure` traduz o status word para uma frase; se sobrar
"Resposta NFC inesperada (status XXXX)", o número é o que falta investigar.

Para ver o que realmente acontece no aparelho:

```bash
adb logcat -s GodotNfc:* NfcService:* BrcmNfcJni:* godot:*
```

## Por que a câmera é embutida, e não o Google Code Scanner

A primeira versão usava o Google Code Scanner, que dispensa a permissão de
CAMERA e não exige integrar preview nenhum — atraente no papel. Na prática ele
abre **uma activity do Play Services**, e isso manda o jogo para segundo plano.
Um app deste tamanho, com câmera e ML Kit carregando por cima, é candidato
natural a ser recolhido por memória: o sintoma era o app "reiniciar" ao voltar da
leitura, perdendo o pareamento.

Não existe como impedir o Android de recolher um processo em segundo plano.
Existe como nunca ir para segundo plano: `onMainCreate` devolve uma `View` que a
Godot encaixa por cima da superfície do jogo, e CameraX + ML Kit rodam ali
dentro. Nenhuma troca de activity.

Dois detalhes que custaram compilação:

- `GodotPlugin` **não** tem `getPluginView()` nesta versão; o gancho é
  `onMainCreate(Activity?): View?`, com o parâmetro anulável.
- O plugin precisa ser um `LifecycleOwner` para o CameraX, e abaixo de
  `lifecycle-runtime` 2.6 essa interface ainda é Java com `getLifecycle()`. A
  versão está fixada em 2.8.7 para a forma Kotlin (`val lifecycle`) valer.

Sobra uma rede de segurança para o caso de o processo morrer por outro motivo: o
resultado da leitura é gravado em `SharedPreferences` **antes** de ser emitido, e
o jogo retoma o pareamento na abertura seguinte. O payload traz jogo, endereços e
código, então o estado é reconstruído inteiro a partir dele.

## O que saiu: `GodotNearbyPlugin`

Havia um quarto plugin, sobre o Nearby Connections do Play Services. Ele
funcionava e mesmo assim foi removido: `Nearby.getConnectionsClient` administra
os rádios por conta própria e **ligava o Wi-Fi do aparelho** assim que a tela de
entrar numa partida chamava `startDiscovery`. Custava ainda permissão de
localização e cinco permissões de Bluetooth no manifesto.

Nada disso aparecia no código do app — não há linha para revisar quando o efeito
colateral mora dentro da dependência. Só sai no aparelho.

Junto com ele saíram `play-services-nearby` do Gradle, as permissões de
Bluetooth e `NEARBY_WIFI_DEVICES` do manifesto, e o `.aar` caiu de 36KB para
27KB. Quem está lado a lado sem internet usa o NFC ou o hotspot local.

Se o singleton não existir no build, o `*_bridge.gd` correspondente retorna
`false` em `is_available()` e a UI desabilita o botão ou cai no caminho
alternativo. Nenhum erro, nenhum crash.

## Por que "sem estar na mesma rede" precisa de plugin

Dois celulares próximos mas em redes diferentes (ou sem Wi-Fi nenhum) não se
enxergam. A solução que não depende de servidor: o anfitrião abre um **hotspot
local** (`WifiManager.startLocalOnlyHotspot`) — uma rede temporária, sem
compartilhar internet, com SSID e senha gerados pelo Android — e o convidado
entra nela. As credenciais viajam dentro do próprio QR Code / toque NFC, que é
justamente o canal fora-de-banda que essa API pressupõe.

Do lado do convidado, entrar na rede não basta: é preciso
`ConnectivityManager.bindProcessToNetwork()`, senão os sockets continuam saindo
pelos dados móveis e o ENet nunca chega ao anfitrião. Isso está em
`GodotWifiLinkPlugin.joinHotspot`.

Requisitos: API 26+ para o hotspot, API 29+ para o `WifiNetworkSpecifier`, e
`ACCESS_FINE_LOCATION` concedido em tempo de execução (o Android exige isso para
abrir hotspot na maioria das versões).

## Por que NFC precisa de plugin

A Godot não expõe NFC em nenhuma plataforma. Além disso, o Android Beam (o push
NDEF peer-to-peer que todo tutorial antigo mostra) foi **removido** da
plataforma. O caminho atual para "encostar dois celulares" é assimétrico:

- **anfitrião**: Host Card Emulation (HCE) — o celular finge ser um cartão
  contactless e responde ao SELECT do AID `F0 43 48 45 53 53` com o payload;
- **convidado**: reader mode — envia o SELECT e lê a resposta.

Ou seja, quem cria a partida ativa o HCE, quem entra ativa o leitor. Os dois
lados são implementados aqui.

Limitação conhecida: alguns aparelhos só respondem ao HCE com a tela ligada e
desbloqueada, e o alcance é de poucos centímetros — encoste as partes de trás
dos aparelhos, geralmente perto da câmera.

## Estrutura

Este diretório **é** um projeto Gradle completo. Os três plugins saem num único
`.aar`, porque a Godot 4 descobre plugins por `meta-data` no manifesto — um
arquivo, três singletons:

```
android_plugin/
  settings.gradle  build.gradle  gradle.properties  local.properties
  gradlew  gradle/wrapper/          (copiados do android_source.zip do template)
  plugin/
	build.gradle
	src/main/AndroidManifest.xml    meta-data v2 + serviço HCE
	src/main/java/org/chessandcheckers/{nfc,qr,wifi}/*.kt
	src/main/res/xml/apduservice.xml
	src/main/res/values/strings.xml
```

As versões em `build.gradle` (AGP 8.6.1, Kotlin 2.1.21, compileSdk 36, Java 17)
espelham o `config.gradle` de dentro do `android_source.zip` da própria Godot.
Divergir disso é a causa clássica de erro de metadados do Kotlin na hora de
exportar.

O `godot-lib` entra como `compileOnly "org.godotengine:godot:4.7.1.stable"` —
está publicado no Maven Central. Tem que ser `compileOnly`: com `implementation`
o APK acaba com duas cópias das classes Java da engine.

## Como construir

```bash
cd android_plugin && ./gradlew :plugin:assembleRelease
```

Precisa de `JAVA_HOME` apontando para um **JDK 17** e de um `local.properties`
com `sdk.dir` usando **barras normais** (`C:/Users/.../Android/Sdk`) — barra
invertida em arquivo `.properties` é escape e o AGP falha com "sintaxe do nome
do arquivo incorreta", sem dizer qual arquivo.

O resultado sai em `plugin/build/outputs/aar/ChessAndCheckersPlugins.release.aar`
e vai para `res://android/plugins/` junto do `.gdap`, que declara as dependências
remotas (o `.aar` não carrega as transitivas):

```ini
[config]
name="ChessAndCheckersPlugins"
binary_type="local"
binary="ChessAndCheckersPlugins.release.aar"

[dependencies]
remote=["androidx.annotation:annotation:1.9.1", "com.google.android.gms:play-services-code-scanner:16.1.0"]
```

Depois disso o export precisa de `gradle_build/use_gradle_build=true` e do
template de build dentro do projeto (`res://android/build/`).

### Armadilha do caminho com `&`

A Godot invoca o `gradlew.bat` pelo `cmd.exe` **sem aspas**. Com o projeto em
`Documents\chess&checkers`, o `&` corta a linha de comando e o build morre com
`'checkers\android\build\' não é reconhecido como um comando interno`. A saída
usada aqui foi um junction sem o caractere:

```powershell
New-Item -ItemType Junction -Path "C:\Users\lucas\Documents\chess-checkers" -Target "C:\Users\lucas\Documents\chess&checkers"
```

e exportar apontando `--path` para o junction. Renomear a pasta resolve de vez.

## Testando

Não dá para testar NFC nem hotspot local em emulador. Com dois aparelhos
físicos:

1. Anfitrião: menu → "Criar partida"; a tela mostra o QR e o código. Com o
   plugin de Wi-Fi presente, ela informa que a rede direta está no ar.
2. Convidado: menu → "Entrar em uma partida" → "Escanear QR Code" ou "Encostar
   celulares (NFC)".
3. Para NFC, encoste as costas dos aparelhos até o som/vibração.

Para isolar um problema, vá do mais simples ao mais complexo:

| Sintoma | Provável causa |
| --- | --- |
| código digitado funciona, QR/NFC não | plugin de QR ou de NFC |
| QR/NFC parear mas não conectar | `bindProcessToNetwork` / permissão de localização |
| nada funciona no mesmo Wi-Fi | isolamento de clientes no roteador |
