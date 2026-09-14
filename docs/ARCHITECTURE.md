# Arquitetura Unificada do Sistema — Destruction Simulator

Documento técnico canônico e *Single Source of Truth* que consolida a arquitetura de software, mapeamento de scripts, modelo de rede, pipeline de física, regras de economia, segurança autoritária, ciclo de vida de inventário e persistência de dados.

> [!IMPORTANT]
> **Regras para Agentes de IA e Invariantes do Sistema:** Antes de propor alterações, refatorações ou correções de bugs, todo desenvolvedor e agente de IA deve consultar e obedecer rigorosamente as diretrizes em [.agents/rules/AI_RULES.md](file:///.agents/rules/AI_RULES.md) e os registros de decisão em [docs/adr/](file:///docs/adr/).

---

## 1. Visão Geral e Filosofia de Engenharia

O projeto adota o padrão de **Autoridade Estrita do Servidor (*Server-Authoritative*) com Renderização e Predição Descentralizadas no Cliente (*Client-Sided Prediction & Debris*)**.

* **Diretório Ativo de Produção:** `src_destruction/`
* **Mecanismo de Sincronização:** `scriptsync` (bidirecional Studio <-> disco). É terminantemente proibido utilizar Rojo.
* **Tipagem Estrita Luau:** Módulos compartilhados e de infraestrutura adotam `--!strict`.
* **Distribuição de Responsabilidades:**
  - **Servidor (Server):** Validação de regras de negócio, limites de disparo (*rate limiting*), raycasts de validação, mutação de inventário, DataStore e integridade do grid de blocos.
  - **Cliente (Client):** Input do jogador, efeitos visuais (VFX), reprodução de áudio, feedback háptico e simulação local de física dos destroços para latência percebida de 0ms.
* **Bases de Referência:**
  - `ref_doomspire`: Mecânicas balísticas de armas, animações `RocketIn`/`RocketOut`, impulsos (*Bomb Jump*) e partículas.
  - `Ref_destructionsimulator`: Voxelização de destruição, grid espacial e regeneração de áreas.
  - `ref_ps99`: Padrões de interface (UI/UX), inventário, lojas e modais.
  - `ItalianBrainrotSimulator`: Estrutura de persistência do DataStore `"r"`, comandos admin (`/e`), modularização de `__DIRECTORY` e leaderboard.

---

## 2. Mapeamento de Scripts e Componentes

### 2.1 ServerScriptService (`src_destruction/ServerScriptService`)

| Módulo / Script | Tipo | Responsabilidade Principal |
| :--- | :--- | :--- |
| `Library/Datastore.luau` | Module | Wrapper resiliente do `DataStoreService` com backoff exponencial para operações de rede. |
| `Library/Network.luau` | Module | Abstração de rede para roteamento de `RemoteEvent` e `RemoteFunction` com criação sob demanda. |
| `Library/Saving.luau` | Module | Gerenciamento de persistência no DataStore `"r"`, controle de sessão (*Session Locking*), auto-save periódico e cache em memória. |
| `Library/RewardsManager.luau` | Module | Cálculo autoritário de moedas e experiência concedidas na quebra de blocos, aplicando multiplicadores de float e buffs. |
| `Library/SellManager.luau` | Module | Conversão de blocos armazenados na mochila em `Cash` e `XP` na zona de venda. Aplica multiplicador de float da mochila ao Cash. |
| `Library/SkinEquip.luau` | Module | Mapeamento de skins equipadas por arma e aplicação de propriedades visuais e multiplicadores. |
| `Library/SkinUnboxing.luau` | Module | Sistema gacha determinístico com distribuição ponderada de raridades e cálculo determinístico de *Float*. |
| `Library/TradeUpContract.luau` | Module | Contratos de fusão no estilo *CS:GO* (10 skins de mesma raridade combinam para 1 skin de raridade superior com média de floats). |
| `Library/RAP_Validator.luau` | Module | Cálculo do Preço Médio Recente (*RAP*) via Média Móvel Exponencial (EMA) com rejeição de outliers e proteção anti-manipulação. |
| `Library/OrbsManager.luau` | Module | Gerenciamento e validação de orbs coletáveis no servidor com verificação de proximidade e tempo de vida. |
| `Library/SanitizeInput.luau` | Module | Sanitização estrita de dados recebidos: rejeição de `NaN`, infinitos, magnitudes vetoriais excessivas e strings malformadas. |
| `Scripts/Core/GameInit.server.luau` | Server | Bootstrap do servidor, handshake de entrada do jogador (`intro`), agendamento de auto-save e replicação de atributos (10Hz). |
| `Scripts/Core/AdminCommands.server.luau` | Server | Interpretador de comandos administrativos com prefixo `/e` (`addCommand`) para teleporte, concessão de moedas e depuração. |
| `Scripts/Game/WeaponsController.server.luau`| Server | Validação de disparos de armas (origem, direção, *leaky bucket* rate limiting) e broadcast via `RenderProjectileEvent`. |
| `Scripts/Game/ExplosionService.server.luau` | Server | Validação de explosões (`HandleExplosion`), detecção de blocos via `GetPartBoundsInRadius`, desancoragem escalonada (`INV-009`) e spawn de orbs. |
| `Scripts/Game/DestructionLoop.server.luau` | Server | Validação de acertos de armas (`WeaponHit`) com verificação de proximidade e rate limit estrito. |
| `Scripts/Game/AreaManager.luau` | Module | Spatial grid hash, integridade estrutural via BFS, desancoragem em onda de choque e reconstrução automática de áreas a 70% de destruição. |
| `Scripts/Game/WeaponEquipService.server.luau`| Server | Validação de posse de armas/mochilas na GearShop, equipagem no personagem e recálculo de capacidade da mochila. |
| `Scripts/Game/ShopService.server.luau` | Server | Transações da GearShop, fornecimento do perfil e execução de venda de blocos. |
| `Scripts/Game/ExclusiveShopService.server.luau`| Server | Venda de Caixas Exclusivas por Contratos e processamento seguro de Gamepasses e Developer Products. |
| `Scripts/Game/TradingService.server.luau` | Server | Motor de trocas P2P com máquina de estados de dupla confirmação e commit atômico com Session Lock. *(Detalhes em [TRADING_SYSTEM.md](file:///docs/systems/TRADING_SYSTEM.md))*. |
| `Scripts/Game/RebirthService.server.luau` | Server | Validação e execução de Rebirth (Tier 1 no Level 75): reseta moedas/armas base, incrementa Rebirth e preserva todas as skins. |
| `Scripts/Game/CarpetService.server.luau` | Server | Controle de equipamento e mecânica de voo do Tapete Voador para jogadores com Rebirth ativo. |
| `Scripts/Game/WorldService.server.luau` | Server | Gerenciamento de mundos (*Spawn* e *Magic*), verificação de requisitos (Rebirth 1 + Level 75) e teleporte seguro. |

---

### 2.2 StarterPlayer (`src_destruction/StarterPlayer`)

| Controlador / Script | Tipo | Responsabilidade Principal |
| :--- | :--- | :--- |
| `Scripts/Game/RocketController.local.luau` | Client | Trajetória balística de projéteis locais, raycasting preditivo, detecção fast-path de impacto em blocos e efeitos VFX de explosão. |
| `Scripts/Game/AreaInfoController.local.luau`| Client | Atualização dinâmica de SurfaceGuis nos totens de entrada das áreas, exibição de nível requerido e controle de colisão da barreira (`Walls.Level`). |
| `Scripts/Game/WorldLoader.local.luau` | Client | Controle da transição visual de mundos, animações de loading screen e handshake com `WorldService`. |
| `Scripts/Game/InteractController.local.luau`| Client | Interações por ProximityPrompt e cliques em NPCs, totens de loja, portais de mundos e interfaces. |
| `Scripts/Game/OrbsFrontend.local.luau` | Client | Renderização e atração magnética de orbs para o personagem com texturas dinâmicas por mundo (*Spawn* vs *Magic*). |
| `Scripts/Game/CarpetController.local.luau` | Client | Física de navegação do Tapete Voador no cliente (velocidade, subida, descida e estabilização). |
| `Scripts/GUIs/HUDController.local.luau` | Client | Atualização de moedas, blocos, ícones e gradientes temáticos por mundo em tempo real. |
| `Scripts/GUIs/RebirthController.local.luau` | Client | Interface modal de Rebirth com exibição de multiplicadores, status de requisitos e confirmação. |
| `Scripts/GUIs/UnboxingController.local.luau`| Client | Roleta de abertura de caixas exclusivas com física de desaceleração suave e efeitos sonoros de tick. |

---

## 3. Pipeline de Física e Destruição Escalonada

### 3.1 O Problema de Escalar a Física em Hardware Fraco
Em simuladores de destruição, uma explosão de raio médio atinge entre 50 e 250 blocos simultaneamente. Em implementações ingênuas, todas as peças são desancoradas (`Anchored = false`) no mesmo instante no Frame 0. Isso gera um pico massivo de cálculo de colisão (*manifold collision generation*), congelando o jogo em dispositivos de baixo desempenho (laptops integrados e celulares).

### 3.2 Solução Arquitetural: Onda de Choque Escalonada (`INV-009`)
A destruição foi estritamente desacoplada em duas etapas:

1. **Destruição Lógica Imediata (Frame 0):**
   - Os blocos atingidos são imediatamente removidos do spatial hash grid (`removePartFromGrid`).
   - O contador de destruição da área é incrementado (`state.destroyedBlocks = state.destroyedBlocks + 1`).
   - A contagem de voxels é processada instantaneamente para que o jogador receba moedas, XP e sons com **0ms de atraso**.
   - Os blocos recebem o atributo `DestroyScheduled = true`, impedindo duplo processamento por tiros simultâneos.

2. **Desancoragem Física Escalonada (*Staggered Shockwave Physics*):**
   - Os blocos válidos são ordenados pela distância do epicentro da explosão (`(part.Position - hitPosition).Magnitude`).
   - **Lote Inicial (Epicentro):** Os primeiros 15 blocos desancoram no Frame 0 (`staggerDelay = 0`), criando o impacto visual imediato do disparo.
   - **Lotes Periféricos (Onda Expansiva):** Os blocos restantes desancoram em lotes de 15 blocos com intervalo de `0.03s` (~1 frame):
     ```lua
     local BATCH_SIZE = 15
     local BATCH_INTERVAL = 0.03
     local batchIndex = math.floor((i - 1) / BATCH_SIZE)
     local staggerDelay = batchIndex * BATCH_INTERVAL
     ```
   - A engine física do Roblox nunca processa mais de 15 novos corpos rígidos colidindo por frame, mantendo a taxa de quadros estável em 60 FPS.
   - A propriedade `CanCollide` permanece ativada (`true`) para que os blocos saltem e quiquem no chão de forma realista.

3. **Integridade Estrutural Agendada (*Debounced Structural Integrity*):**
   - A verificação de partes flutuantes via BFS (`RunStructuralIntegrity`) é agendada via `ScheduleStructuralIntegrity` com debounce de `0.15s`.
   - O desabamento de estruturas sem suporte ocorre naturalmente após a passagem da onda de choque, distribuindo a carga de CPU.

---

## 4. Curva de Progressão e Requisitos de Nível

O balanceamento de níveis e mundos foi padronizado em progressões aritméticas consistentes:

```
[Mundo 1: Spawn] ──────────────────────────────────────────► [Rebirth 1 & Mundo 2]
 Área 1: Nível 10 (Acesso Livre para Iniciantes)               Nível Requerido: 75
 Área 2: Nível 20 (+10)                                        Rebirth Requerido: 1
 Área 3: Nível 30 (+10)                                                  │
 Área 4: Nível 40 (+10)                                                  ▼
 Área 5: Nível 50 (+10)                                       [Mundo 2: Magic]
 Área 6: Nível 60 (+10)                                        Área 7:  Nível 75
                                                               Área 8:  Nível 100 (+25)
                                                               Área 9:  Nível 125 (+25)
                                                               Área 10: Nível 150 (+25)
                                                               Área 11: Nível 175 (+25)
                                                               Área 12: Nível 200 (+25)
```

### 4.1 Salvaguarda de Iniciantes na Área 1
Embora a Área 1 seja configurada como Nível 10 na tabela de progressão das áreas, tanto o cliente ([AreaInfoController.local.luau](file:///c:/Users/Reitora%2002/Desktop/RobloxProjects/Games/PS99/src_destruction/StarterPlayer/Scripts/Game/AreaInfoController.local.luau)) quanto o servidor ([ExplosionService.server.luau](file:///c:/Users/Reitora%2002/Desktop/RobloxProjects/Games/PS99/src_destruction/ServerScriptService/Scripts/Game/ExplosionService.server.luau)) possuem uma regra de segurança explícita que mantém a barreira da Área 1 permanentemente aberta e seus blocos quebráveis por jogadores de Nível 1. Isso impede que novos jogadores fiquem bloqueados no lobby inicial sem conseguir obter experiência.

---

## 5. Ciclo de Vida de Armas, Skins e Inventário

### 5.1 Regras de Posse: Armas Base vs. Skins (`INV-001` e `INV-002`)
1. **Armas Base (*Types*):** São ferramentas funcionais adquiridas exclusivamente com moedas na **GearShop** (ou armas padrão iniciais: `Rocket Launcher`, `Bomb`, `SmallBag`). Ficam registradas em `profile.Weapons` e `profile.Backpacks`.
2. **Skins:** São itens cosméticos colecionáveis obtidos em caixas exclusivas, trocas ou contratos de fusão. Ficam em `profile.Skins`.
3. **Regra Canônica:** Possuir uma skin **NUNCA** concede a arma base. Para equipar qualquer skin, o jogador é obrigado a comprar primeiro a respectiva arma base na GearShop. Caso tente equipar sem possuir a arma, a interface exibe a notificação padrão:
   `"You must purchase the [ItemName] in the GearShop first to equip this!"`

### 5.2 Modo de Exclusão de Skins (*Delete Mode*)
Para evitar que o inventário fique saturado no limite máximo de 100 skins (o que bloquearia a abertura de novas caixas):
- A interface `Inventory.Frame.Main.Search` dispõe dos controles `DeleteSelect`, `Delete` e `Back`.
- **Skins Default Protegidas:** Skins base/padrão ficam ocultas durante o modo delete e nunca podem ser excluídas.
- **Skins Trancadas:** Itens marcados como favoritos/trancados (`Locked == true`) são imunes à seleção para exclusão.
- **Confirmação em Duas Etapas:** Exige a seleção prévia de pelo menos um item e confirmação através de modal afirmativo (*"Are you sure you want to delete these skins? This cannot be undone."*).

---

## 6. Persistência de Dados e Session Locking

A persistência consome o `DataStoreService` com a chave de partição `"r"` e adota as seguintes garantias de integridade:
* **Session Locking Atômico:** Ao entrar no servidor, o perfil do jogador é reivindicado via `UpdateAsync()`. Se outra sessão ainda mantiver a trava ativa, a entrada é retida até a liberação segura, prevenindo duplicações de inventário.
* **Auto-Save Distribuído:** Salvamento automático a cada 5 minutos com jitter aleatório para evitar picos simultâneos de requisições ao DataStore.
* **Preservação de Dados em Rebirth:** A função `RebirthService` reseta estritamente moedas e armas base para o kit inicial. Skins, Gemas, Contratos e Mundos desbloqueados são permanentemente preservados no perfil.

---

## 7. Roadmap Técnico Futuro

* **Serialização Binária de Orbs via Luau Buffers:**
  Migração do envio de orbs coletáveis de dicionários JSON para buffers Luau compactos de **16 bytes por orb**:
  - `ID do Orb (U16)`: 2 bytes
  - `Posição X, Y, Z (F32)`: 12 bytes
  - `Valor em Blocos (U16)`: 2 bytes
  Essa otimização reduzirá o payload de rede do `OrbsManager` em mais de 75%, liberando ainda mais banda em sessões com disparos massivos.
* **Compressão Zstandard no DataStore:**
  Aplicação de `EncodingService:CompressBuffer()` em inventários de grande escala antes de invocar o `DataStoreService`, assegurando conformidade com folga em relação ao teto de 4MB por registro.
