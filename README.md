# B.E.P — Destruction Simulator Engine (Roblox / Luau)

[![Luau](https://img.shields.io/badge/Language-Luau-00A2FF?style=flat-square&logo=lua)](https://luau-lang.org/)
[![Roblox](https://img.shields.io/badge/Platform-Roblox%20Studio-EE3124?style=flat-square&logo=roblox)](https://www.roblox.com/)
[![Genre](https://img.shields.io/badge/Genre-Destruction%20Simulator-orange?style=flat-square)](#core-loop--game-design)
[![Architecture](https://img.shields.io/badge/Architecture-Server%20Authoritative%20%7C%20Zero--Physics%20Server-success?style=flat-square)](#arquitetura-de-física-zero-server-lag)
[![License](https://img.shields.io/badge/License-Proprietary-red?style=flat-square)](#)

Motor de alta performance para **Destruction Simulator** no Roblox, construído em Luau. Desenvolvido com foco em escalabilidade e baixa latência para execução estável em dispositivos de baixo desempenho (mobile e PCs modestos), combinando física visual cliente-side, contabilidade de blocos puramente numérica e um ecossistema econômico perpétuo guiado por *Floats* de Skins.

---

## Core Loop & Game Design

```
[ Farm de Blocos ] ──> [ Capacidade da Mochila ] ──> [ Venda (Sell Zone) ] ──> [ Upgrades & Rebirth ]
 (Arma + Mina +          (Dita o ritmo de jogo         (Conversão em Cash        (Reseta armas/áreas,
  Skin Float Mult)        voltando à base)              + XP c/ Backpack Mult)    preserva Skins e RAP)
```

### 1. Setup & Farm (Fase de Ação e Retenção)
- **Retenção Imediata:** Concessão inicial de *StarterBooster* gratuito, retendo o jogador nos primeiros minutos críticos sem fricção de compras.
- **Armas e Minas:** O jogador destrói estruturas no mapa gerando "Blocos".
- **Zero-Lag Server:** Os blocos farmados **não são partes físicas no servidor**. São computados como variáveis numéricas atômicas diretamente no estado do jogador.
- **Weapon Skin Multiplier:** O atributo **Float** da skin equipada na arma multiplica diretamente a taxa de blocos coletados por explosão.

### 2. Armazenamento (Fase de Controle e Ritmo)
- A capacidade da **Mochila** limita o armazenamento de blocos, estabelecendo a cadência do loop e incentivando retornos estratégicos à base.

### 3. Venda & Recompensa (Fase de Economia)
- **Sell Zone:** Descarrega os blocos acumulados e os converte instantaneamente em **Cash** e **XP**.
- **Backpack Skin Multiplier:** O atributo **Float** da skin equipada na mochila atua com um multiplicador dedicado sobre o **Cash** final recebido.

### 4. Reinvestimento & Rebirth (Economia Perpétua & Anti-Inflação)
- **Upgrades:** Aquisição progressiva de tiers superiores de Armas, Minas e Mochilas.
- **Rebirth com Preservação de Ativos:** O jogador reinicia o progresso de armas e áreas, mas **mantém 100% de suas Skins**, protegendo seu investimento e o valor de mercado (RAP).
- **Demanda Contínua das Skins Iniciais:** Para equipar uma skin após o Rebirth, o jogador deve recomprar a arma base correspondente. Isso sustenta a procura de veteranos por skins das primeiras áreas para acelerar novos ciclos.
- **Ralo de Itens (Item Sink):** O sistema de **Fusão** consome skins excedentes com base em seu peso estatístico, contendo a inflação e assegurando liquidez e valor de mercado sustentáveis.

---

## Arquitetura de Física (Zero-Server-Lag)

Cenários destrutíveis em larga escala (10.000 a 50.000+ peças) geram gargalos severos de simulação física se processados no servidor. A solução implementada isola completamente a física no cliente:

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

- **Servidor Leve:** O servidor processa apenas queries espaciais restritas a blocos marcados com `CollectionService`, converte o impacto em blocos numéricos e remove as peças sem inicializar instâncias físicas ativas.
- **Micro-Batching no Cliente:** Para evitar quedas bruscas de taxa de quadros (FPS) em hardware modesto, os clientes desancoram os estilhaços visuais em lotes fracionados (**30 partes a cada 0.03s**), estabilizando o frame rate.

---

## Estrutura do Repositório

```
├── docs/                       # Documentação técnica e arquitetura detalhada
│   ├── ARCHITECTURE.md         # Especificações completas de física, curvas e persistência
│   ├── adr/                    # Architecture Decision Records
│   └── systems/                # Documentação técnica de subsistemas (Trocas, Inventário, etc.)
├── ReplicatedStorage/          # Módulos compartilhados, tabelas de dados e eventos remotos
├── ServerScriptService/        # Serviços autoritários de física, economia e salvamento
├── StarterGui/                 # Componentes de interface e renderização 3D (ViewportFrames)
├── StarterPlayer/              # Controladores cliente, micro-batching e câmeras
└── README.md                   # Documento de apresentação do projeto
```
