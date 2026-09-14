# 💥 B.E.P — Destruction Simulator Engine (Roblox / Luau)

[![Luau](https://img.shields.io/badge/Language-Luau-00A2FF?style=flat-square&logo=lua)](https://luau-lang.org/)
[![Roblox](https://img.shields.io/badge/Platform-Roblox%20Studio-EE3124?style=flat-square&logo=roblox)](https://www.roblox.com/)
[![Genre](https://img.shields.io/badge/Genre-Destruction%20Simulator-orange?style=flat-square)](#-core-loop--game-design)
[![Architecture](https://img.shields.io/badge/Architecture-Server%20Authoritative%20%7C%20Zero--Physics%20Server-success?style=flat-square)](#-arquitetura-de-f%C3%ADsica-zero-server-lag)
[![License](https://img.shields.io/badge/License-Proprietary-red?style=flat-square)](#)

Motor de alta performance para **Destruction Simulator** no Roblox, construído em Luau. Desenvolvido com foco em escalabilidade e baixa latência para rodar suave em dispositivos de baixo desempenho (mobile e PCs modestos), combinando física visual cliente-side, contabilidade de blocos puramente numérica e um ecossistema econômico perpétuo guiado por *Floats* de Skins.

---

## 🔄 Core Loop & Game Design

```
[ Farm de Blocos ] ──> [ Capacidade da Mochila ] ──> [ Venda (Sell Zone) ] ──> [ Upgrades & Rebirth ]
 (Arma + Mina +          (Dita o ritmo de jogo         (Conversão em Cash        (Reseta armas/áreas,
  Skin Float Mult)        voltando à base)              + XP c/ Backpack Mult)    preserva Skins e RAP)
```

### 1. Setup & Farm (Fase de Ação e Retenção)
- **Retenção Imediata:** Pop-up inicial concedendo um *StarterBooster* gratuito, retendo o jogador nos minutos mais críticos sem sobrecarga de anúncios de gamepasses.
- **Armas e Minas:** O jogador destrói estruturas no mapa gerando "Blocos".
- **Zero-Lag Server:** Os blocos farmados **não são partes físicas no servidor**. São computados como variáveis numéricas atômicas diretamente no estado do jogador.
- **Weapon Skin Multiplier:** O atributo **Float** da skin equipada na arma multiplica diretamente a taxa de blocos coletados por explosão.

### 2. Armazenamento (Fase de Controle e Ritmo)
- A capacidade da **Mochila** limita o armazenamento de blocos, estabelecendo a cadência do loop e incentivando retornos estratégicos à base.

### 3. Venda & Recompensa (Fase de Economia)
- **Sell Zone:** Descarrega os blocos acumulados e os converte instantaneamente em **Cash** e **XP**.
- **Backpack Skin Multiplier:** O atributo **Float** da skin equipada na mochila atua com um multiplicador dedicado sobre o **Cash** final recebido.

### 4. Reinvestimento & Rebirth (Economia Perpétua & Anti-Inflação)
- **Upgrades:** Compra de tiers avançados de Armas, Minas e Mochilas.
- **Rebirth com Preservação de Ativos:** O jogador reseta o progresso de armas e áreas, mas **mantém 100% de suas Skins**, blindando o investimento e o valor de mercado (RAP).
- **Utilidade Perpétua das Skins Iniciais:** Para equipar uma skin pós-rebirth, o jogador deve recomprar a arma base correspondente. Isso gera demanda contínua de veteranos por skins das primeiras áreas para acelerar o reinício do ciclo.
- **Ralo de Itens (Item Sink):** O sistema de **Fusão** consome skins excedentes com base em seu peso estatístico, controlando a inflação e mantendo a raridade de mercado sustentável.

---

## ⚡ Arquitetura de Física (Zero-Server-Lag)

Ambientes destrutíveis de 10.000 a 50.000+ peças costumam causar engasgos severos se processados pelo servidor.

```
[Ação de Explosão / Mina]
           │
           ▼
[Query Espacial no Servidor] ──── (GetPartBoundsInRadius / Tag Filter)
           │
           ├──> [Servidor] ──> Contabiliza Blocos como Número (Sem física, 0 Server Lag)
           │
           └──> [RemoteEvent] ──> Transmite CFrame / Cor para Clientes Próximos
                                         │
                                         ▼
                               [Pipeline Micro-Batch no Cliente]
                               (Desancoragem escalonada: 30 peças / 0.03s)
                                         │
                                         ▼
                               [Estilhaços / Debris / Áudio]
```

- **Servidor Leve:** O servidor apenas executa queries espaciais restritas a blocos marcados com `CollectionService`, converte o dano em blocos numéricos e remove as peças sem ativar física de colisão.
- **Micro-Batching no Cliente:** Para evitar travamentos em celulares ou computadores básicos, o cliente desancora os estilhaços visuais em lotes fracionados (**30 partes a cada 0.03s**), mantendo a taxa de quadros (FPS) estável.

---

## 🤝 Sistema de Trocas (P2P Trading)

- Máquina de estados de 5 etapas com trava mútua:
  $$\text{Idle} \longrightarrow \text{Trading} \longrightarrow \text{Locked} \longrightarrow \text{Countdown (3s)} \longrightarrow \text{Atomic Commit}$$
- **Anti-Exploit:** Validação de posse em duas fases (no lock e no commit final). Se qualquer oferta for alterada durante a confirmação, o estado é cancelado de volta para *Staging*, impedindo golpes de troca rápida (*Last-Second Switch*).

---

## 📂 Estrutura do Repositório

```
├── docs/                       # Especificações técnicas e arquiteturais
│   ├── ARCHITECTURE.md         # Motor de física, micro-batching e curvas de progressão
│   ├── adr/                    # Architecture Decision Records
│   └── systems/
│       └── TRADING_SYSTEM.md   # Protocolo e segurança da máquina de trocas
├── ReplicatedStorage/          # Módulos compartilhados, configs de itens e remotes
├── ServerScriptService/        # Controllers autoritários de física, economia e persistência
├── StarterGui/                 # Interfaces (Loja, Mochila, HUD, Trocas, ViewportFrames 3D)
├── StarterPlayer/              # Controladores cliente, micro-batch de debris e câmera
└── README.md                   # Apresentação do projeto
```

---

## 🛠️ Desenvolvimento & Sincronização

- **Sincronização Bidirecional:** Utiliza **ScriptSync** integrado com o Roblox Studio.
- **Aviso:** Nunca utilizar Rojo neste projeto para preservar a integridade das instâncias sincronizadas.
