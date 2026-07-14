---
title: "多Agent编排之langgraph调度"
date: 2025-11-16T00:13:00+08:00
draft: true
---

现在 agent 开发形势，就和当初前端从蛮荒时代进入到vue/react/solid框架时代一样，花式复杂啊，尤其是拆分成多个 agent 后，调度管理就变得复杂起来。

**多Agent核心问题不是调用多个 Agent，而是管理一个长期、可中断、可恢复、可分支的工作流。**
<!--more-->
## 1. 多Agent核心问题

多 Agent 一旦复杂起来，会遇到这些问题：

| 问题 | 本质 |
|---|---|
| Agent 谁先执行、谁后执行 | 控制流 |
| 上一个 Agent 的结果怎么传给下一个 | 状态管理 |
| 某个 Agent 失败后怎么重试或降级 | 错误恢复 |
| 用户中途取消、暂停、恢复 | 生命周期管理 |
| 中间结果怎么保存 | checkpoint |
| UI 怎么展示当前阶段 | 过程事件 |
| 是否需要根据结果走不同分支 | 条件路由 |
| 多轮研究如何接着上次状态继续 | 可恢复执行 |

这些东西如果不用框架，也能写，但会逐渐变成你自己手写一个“工作流引擎”。
多 Agent 系统的复杂度主要来自“状态流转”，不是来自“Agent 调用”，所以LangGraph用了有向图处理，但是只靠图不是万能的，也需要工程上架构的实现，后面会讲到。

这个图处理方式，难道是什么新概念吗？

当然不是！！！软件工程界，处处都是相似的思想：K8s 用 Pod 依赖图调度容器，React 用组件树管理渲染——当系统中存在复杂的依赖关系和条件分支时，图是最自然的建模方式。

LangGraph 的价值不是“它能调用Agent”，就像一句名言“当你觉得足够复杂时，就把它分层“，于是 langgraph 把：

```text
节点
边
状态
条件跳转
检查点
中断
恢复
事件流
```

这些能力抽象成一个个独立的分层逻辑。

在之前的简单系统中，我们可以用 `asyncio` / service 编排，开始可能是这样：

```python
plan = await planner.run()
search = await searcher.run(plan)
analysis = await analyst.run(search)
report = await writer.run(analysis)
```

但做着做着就会变成：

```text
如果 planner 结果不足，重新规划
如果 search 失败，换搜索源
如果 analyst 判断证据不足，回到 search
如果用户取消，停止当前任务
如果服务重启，从上次阶段恢复
如果前端刷新，恢复 UI 过程状态
如果某个节点超时，进入降级节点
```

这时已经不是简单函数调用，而是一个图：

{{< mermaid >}}
flowchart TD
    A[Planner] --> B[Searcher]
    B --> C[Analyst]
    C -->|证据不足| B
    C -->|证据充分| D[Writer]
    B -->|搜索失败| E[Fallback Search]
    E --> C
    D --> F[Final Report]
{{< /mermaid >}}

用代码实现这样一幅图，是不是看起来就清爽多了，不用线性函数一堆了，毕竟写代码太容易同步面条式代码了…


## 2. 设计目标

基于LangGraph的设计目标有三点：

1. 用声明式图表达业务逻辑中的标准研究流程。
2. 用 `ResearchState` 作为所有 Agent 共享的状态类型。
3. 用条件边表达审核后的循环和结束决策。

对应的抽象关系是：

```text
节点: 一个 Agent 阶段
边: 阶段之间的固定流转
条件边: 根据 state 决定下一步
ResearchState: 图中所有节点共同读写的全局工作记忆
```

## 3. 架构实现
接下来简单的看一下调度过程：

{{< mermaid >}}
flowchart TD
  Init["DeepResearchGraph.__init__"] --> ImportCheck{"LANGGRAPH_AVAILABLE ?"}
  ImportCheck -- 否 --> NoGraph["self.graph = None\n使用非 LangGraph 路径（兜底编排逻辑）"]
  ImportCheck -- 是 --> Build["_build_langgraph()"]

  Build --> StateGraph["StateGraph(ResearchState)"]
  StateGraph --> Nodes["add_node\nplan / research / analyze / write / review / revise"]
  Nodes --> Entry["set_entry_point('plan')"]
  Entry --> Edges["add_edge\nplan -> research -> analyze -> write -> review"]
  Edges --> Conditional["add_conditional_edges\nreview -> revise 或 END"]
  Conditional --> Loop["add_edge('revise', 'review')"]
  Loop --> Compile["workflow.compile()"]
  Compile --> Graph["self.graph"]
{{< /mermaid >}}

mermaid 图中的每个节点，都是 langgraph 的一个抽象层实现，还是很好用的。

构建入口在 `DeepResearchGraph.__init__()`：

```text
if LANGGRAPH_AVAILABLE:
    self.graph = self._build_langgraph()
else:
    self.graph = self._build_simple_line()
```

`LANGGRAPH_AVAILABLE` 来自模块加载时对 `StateGraph` 和 `END` 的导入结果。这样设计的目的是不增加复杂度，通过配置控制或者后面引入决策层，动态判断，总之这里的目的是 优雅降级到非 LangGraph 路径。

例如某个客户的工作流只是固定流程：`规划 -> 搜索 -> 分析 -> 报告`, 线性编排就足够满足了，这就是兜底层。

### 3.1 图结构

LangGraph 图在 `_build_langgraph()` 中定义：

```text
workflow = StateGraph(ResearchState)

workflow.add_node("plan", self._plan_node)
workflow.add_node("research", self._research_node)
workflow.add_node("analyze", self._analyze_node)
workflow.add_node("write", self._write_node)
workflow.add_node("review", self._review_node)
workflow.add_node("revise", self._revise_node)

workflow.set_entry_point("plan")

workflow.add_edge("plan", "research")
workflow.add_edge("research", "analyze")
workflow.add_edge("analyze", "write")
workflow.add_edge("write", "review")

workflow.add_conditional_edges(
    "review",
    self._should_revise,
    {
        "revise": "revise",
        "complete": END
    }
)

workflow.add_edge("revise", "review")
return workflow.compile()
```

状态图如下：

{{< mermaid >}}
stateDiagram-v2
  [*] --> plan
  plan --> research
  research --> analyze
  analyze --> write
  write --> review
  review --> revise: _should_revise == "revise"
  review --> [*]: _should_revise == "complete"
  revise --> review
{{< /mermaid >}}

这个图表达的是业务中的一个最小闭环：先规划、搜索、分析、写作，再审核。审核不通过时修订，修订后回到审核；审核通过或达到终止条件时结束。

### 3.2 节点到 Agent 的映射

进一步解释langgraph 的抽象节点的映射关系，就是如下：
{{< mermaid >}}
flowchart LR
  subgraph LangGraph["LangGraph nodes"]
    Plan["plan"]
    Research["research"]
    Analyze["analyze"]
    Write["write"]
    Review["review"]
    Revise["revise"]
  end

  subgraph Agents["Agents"]
    Architect["ChiefArchitect"]
    Scout["DeepScout"]
    Wizard["CodeWizard"]
    Writer["LeadWriter"]
    Critic["CriticMaster"]
    Analyst["DataAnalyst\n当前未接入 LangGraph 图"]
  end

  Plan --> Architect
  Research --> Scout
  Analyze --> Wizard
  Write --> Writer
  Review --> Critic
  Revise --> Writer
{{< /mermaid >}}

各节点逻辑如下：

| 节点 | 实现函数 | 阶段 / Agent | 作用 |
| --- | --- | --- | --- |
| `plan` | `_plan_node` | `INIT` / `ChiefArchitect` | 分析问题，生成研究大纲、实体和子问题 |
| `research` | `_research_node` | `RESEARCHING` / `DeepScout` | 搜索资料，沉淀事实和来源 |
| `analyze` | `_analyze_node` | `ANALYZING` / `CodeWizard` | 数据分析和可视化 |
| `write` | `_write_node` | `WRITING` / `LeadWriter` | 撰写最终报告 |
| `review` | `_review_node` | `REVIEWING` / `CriticMaster` | 审核报告并写入质量反馈 |
| `revise` | `_revise_node` | `REVISING` / `LeadWriter` | 根据审核反馈修订报告 |

每个节点的实现，有一个统一的基类实现：

```text
state = dict(state)
state["phase"] = 某个 ResearchPhase
result = await agent.process(state)
return dict(result)
```

先复制状态再改阶段，是为了避免直接改动传入对象时产生难以追踪的副作用；节点返回新的状态字典，让 LangGraph 继续把它交给下一个节点。

不同的节点逻辑，需要自定义实现。
### 3.3 条件边和循环

就像人类做判断一样，多 agent状态之所以复杂，就是因为涉及到了判断后的流转：
例如审核之后的路由函数是 `_should_revise(state)`：

```text
if state["unresolved_issues"] > 0 and state["iteration"] < state["max_iterations"]:
    return "revise"
return "complete"
```

这个函数把审核结果转成 LangGraph 的路由标签：

- `revise`：进入 `revise` 节点。
- `complete`：进入 `END`，结束图执行。

`workflow.add_edge("revise", "review")` 形成回路，因此 LangGraph 图具备“修订后回到审核”的循环能力。

{{< mermaid >}}
flowchart TD
  Review["review\nCriticMaster"] --> Decision{"unresolved_issues > 0\nand iteration < max_iterations ?"}
  Decision -- 是 --> Revise["revise\nLeadWriter"]
  Revise --> Review
  Decision -- 否 --> End["END"]
{{< /mermaid >}}

这里是极简的表达 `review -> revise -> review`。
实际业务中，架构设计我们可以自己决定，但业务逻辑要和客户确认，就像工作流的制定要和客户讨论，不是拍脑袋想出来的。

像我们实际上，还有补充搜索回路，为了避免漏掉信息和信息源的可靠性：`RE_RESEARCHING -> DeepScout -> LeadWriter -> Review` ，等等等的工程实践，都属于定制化了，就不具有普适性了。

### 3.4 主逻辑
前面基础抽象层搞完后，就进入到主逻辑入口了 `_run_with_langgraph(state)`：

```text
yielded_count = 0

async for output in self.graph.astream(state):
    for node_name, node_state in output.items():
        if isinstance(node_state, dict) and "messages" in node_state:
            messages = node_state["messages"]
            new_messages = messages[yielded_count:]
            for message in new_messages:
                yield message
            yielded_count = len(messages)
```
![](/agents/langgraph_sse.png)

`yielded_count` 用于避免重复输出。因为每个节点返回的状态里可能包含累计的 `messages`，执行器只取上次输出之后的新消息。

上面这套基本是标准的langgraph 调度逻辑了，特别洗的细节，可以直接靠文档补全啦，最难的还是工作流的逻辑设计。

我再简单分享一下，我在工程化上的几点优化实践，算是小小的抛砖引玉😋

## 4. 工程化优化
众所周知，大模型如果做各种深入调研，组合多个 agent 的结果进行分析后，在输出，时间会很久，客户也有可能中断任务，毕竟都是在烧 token 呀。

所以如何取消、恢复任务呢？

LangGraph中这两个能力一般不放在“图结构定义”里，而是放在 **节点执行逻辑、运行时控制层、checkpoint saver、事件流封装层** 里实现。

### 4.1 **取消**

LangGraph本身没有取消的功能，业务上我们可以使用 flag 标志，“每 0.5 秒检查取消标志”：

1. 外层运行时创建 `asyncio.Task`
2. 后端维护一个 `cancel_flag`
3. 每 0.5 秒轮询取消标志
4. 如果用户取消，则调用 `task.cancel()`
5. LangGraph 节点内部也要配合处理中断，避免长时间阻塞

例如有这样一个取消的逻辑：

```python
async def run_graph_with_cancel(graph, initial_state, run_id):
    task = asyncio.create_task(graph.ainvoke(initial_state))

    try:
        while not task.done():
            if await cancel_store.is_cancelled(run_id):
                task.cancel()
                raise ResearchCancelled()

            await asyncio.sleep(0.5)

        return await task

    except asyncio.CancelledError:
        await save_cancelled_state(run_id)
        raise
```

但这里又有一个坑点： 
如果某个 LangGraph 节点内部正在执行一个很长的同步调用，比如阻塞式搜索、同步 LLM 请求等等任务，`task.cancel()` 不一定能立刻生效。

所以节点内部最好也做协作式取消：

```python
async def search_node(state):
    if await cancel_store.is_cancelled(state["run_id"]):
        raise ResearchCancelled()

    result = await search_service.search(...)

    if await cancel_store.is_cancelled(state["run_id"]):
        raise ResearchCancelled()

    return {"search_result": result}
```

如果是流式 LLM，可以在 token/chunk 循环中检查取消：

```python
async for chunk in llm.astream(messages):
    if await cancel_store.is_cancelled(run_id):
        raise ResearchCancelled()

    yield chunk
```

这个优化，相当于实现了一个抽象层，哈哈哈真的是万能的分层理论：
- 取消 task， 图运行外层 runtime wrapper
- 节点内及时取消，每个耗时节点内部检查 cancel flag
- 0.5 秒超市检查，外层 task supervisor
- SSE 通知取消，外层捕获取消异常后发送事件

### 4.2 **检查点 / UI 恢复**

LangGraph 有自己的 checkpoint 机制，可以保存 **图状态**，比如当前 state、当前节点、下一步要执行什么。通常通过 checkpointer 实现：

```python
from langgraph.checkpoint.memory import MemorySaver

checkpointer = MemorySaver()

graph = builder.compile(checkpointer=checkpointer)
```

这种内存式的 `MemorySaver`做检查点，小项目可以，但是生产环境时，通常是换成 PostgreSQL、Redis。

运行时需要传入 `thread_id`：

```python
config = {
    "configurable": {
        "thread_id": run_id
    }
}

await graph.ainvoke(initial_state, config=config)
```

恢复时用同一个 `thread_id` 继续：

```python
state = await graph.aget_state(config)
```

但是要注意如果想达到UI 恢复，不光要保存后端图状态，也要保存前端 UI 状态：
- LangGraph checkpoint 保存 agent state、messages、中间结果、下一节点，可以使用LangGraph checkpointer
- UI checkpoint 保存阶段列表、进度、卡片、日志、SSE 事件、展示状态，可以使用 业务表 / Redis / checkpoint 表扩展字段

我设计的是：每个节点返回业务状态后，同时发出一个 UI 事件，并持久化 UI snapshot。

```python
async def analysis_node(state):
    result = await do_analysis(state)

    new_state = {
        "analysis": result,
        "stage": "analysis_done",
    }

    await ui_state_store.save(
        run_id=state["run_id"],
        ui_state={
            "currentStage": "analysis_done",
            "progress": 60,
            "cards": [...],
        },
    )

    return new_state
```

恢复时：

1. 用 LangGraph `thread_id` 恢复后端执行状态
2. 从业务表恢复 UI 状态
3. 前端重新拉取历史事件 / UI snapshot
4. 如果任务未完成，可以继续订阅 SSE

整体结构可以这样理解：

{{< mermaid >}}
flowchart TD
    A[用户发起研究] --> B[创建 run_id / thread_id]
    B --> C[启动 LangGraph task]
    C --> D[节点执行]
    D --> E[LangGraph Checkpoint 保存后端 state]
    D --> F[业务 UI Store 保存 UI snapshot]
    C --> G[Supervisor 每 0.5 秒检查 cancel flag]
    G -->|取消| H[task.cancel]
    H --> I[保存 cancelled 状态并发送 SSE]
    E --> J[后端恢复]
    F --> K[前端 UI 恢复]
{{< / mermaid >}}