# code-review-graph / graphify vs. OmniRoute — local-first code intelligence

## 1. The Truth About Code-Review-Graph / Graphify

It is not an MCP Host. It is a highly specialized MCP Server (a Tool).

- **What it does**: crawls a folder of forked repositories (Fabric, Open Interpreter, Firecrawl, MarkTechpost tutorials) and builds a local, persistent dependency map (a graph database) of how the code connects.
- **Why "for MCP and CLI"**: it exposes that graph data via the Model Context Protocol standard. When an agent asks it a question, it doesn't dump the whole repository — it says "only these 3 lines of code in file X matter to the bug in file Y." That's where the context reductions come from.

## 2. Where OmniRoute Fits (The Router vs. The Map)

If code-review-graph is the Map of the code, OmniRoute is the Traffic Controller sitting in front of the models. OmniRoute doesn't map files — it handles Context Compression and Token Routing. When a prompt or screen frame passes into the Qwen 3.5 models, OmniRoute intercepts it and decides where to get the missing information to fill it out.

## 3. The On-Device Handshake

```
[ USER PROMPT / SCREEN FRAME ]
            │
            ▼
[ OMNIROUTE (The Router) ]
   Intercepts request & calculates token budget space
            │
   ┌────────┴────────┐
   ▼ (Calls MCP tool)  ▼ (Pulls episodic memory)
[ CODE-REVIEW-GRAPH ]   [ MEM0 ]
(prunes repo context    (User Entities)
to bare-minimum lines)
   └────────┬────────┘
            ▼ (Compressed Context Stream)
[ LOCAL INFERENCE (Qwen 3.5 9B) ]
   Executes inside an optimized context window
```

## How to Set This Up

1. **Run the Graph Extractor** — run code-review-graph locally in Termux over the repository storage; it indexes once and sits as a local background daemon.
2. **Initialize OmniRoute** — boot it as the local proxy endpoint.
3. **The Context Compression Loop** — when asking Qwen 3.5 to figure out a script from a MarkTechpost tutorial: OmniRoute catches the prompt, queries the code-review-graph local MCP tool interface for exact code references, code-review-graph returns only the specific snippets that matter (stripping boilerplate), OmniRoute packs those tight code references alongside Mem0 entities, compresses the tokens, and hands the final micro-payload to the NPU.

This is how the benchmarked context reductions get achieved on-device without running out of RAM on the phone's chip.
