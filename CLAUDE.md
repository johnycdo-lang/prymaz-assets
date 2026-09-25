# CLAUDE.md

## Delegação a subagentes

- **Especifique o modelo em cada chamada de subagente** — não deixe no padrão. Heurística
  de partida, ajustável por tarefa: modelo mais forte para arquitetura, bugs complexos e
  revisão de código; modelo intermediário para edições, testes, documentação e
  refatoração; modelo leve para pesquisa exploratória e resumos.
- **Planeje antes de delegar**, um subagente por tarefa — não fatie uma mudança lógica em
  vários agentes picados.
- **Rode subagentes independentes em paralelo** quando as tarefas não dependem uma da
  outra.
- Isso não substitui julgamento: para leituras, comandos rápidos e edições pequenas, o
  orquestrador segue livre para agir diretamente — delegação é para tarefas que
  justificam um subagente dedicado, não para toda ação do dia a dia.
