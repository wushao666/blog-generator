---
title: "多Agent编排之手写调度器"
date: 2026-01-08T23:56:26+08:00
draft: true
---

众所周知目前多 agent 架构下，如何组织、调度各个 agent是个基础工作，业界常见的做法是使用 langgraph 直接做调度，但是我们的客户希望更加精细的展示，每个阶段的调度过程和结果，而 langgraph 只能做到某个阶段完成后才会展示结果，所以我决定自己手写一个调度器，来实现更精细的调度过程展示。
<!--more-->
![](/agents/1.png)
![](/agents/4.png)


## 1. 为什么需要调度器
在手写之前，我们要先搞清楚：为什么当下多 agent 架构必备 langgraph 这类调度器了？

有以下 3 个核心原因和 2 个交互优化原因：

### 1.1  状态机的图实现
曾经我们可以手写代码或者使用 langchain 实现 单agent 功能，也是写的飞起，但随着任务拆分、解耦不同 agent 的功能，单个 agent 处理的任务越来越小，任务之间的依赖关系越来越复杂，agent 之间的协作也越来越频繁。

例如我们客户的一个经典 多 Agent 流程是多阶段实现的：
`plan -> research -> analyze -> write -> review -> revise -> review ... -> complete`

从而形成一个个工作流，而当下ai 时代，我们这些工程师的核心能力就是`抽象业务场景，变成工作流，以任务编排的形式，让 agent 帮我们实现`

它不是：`用户问题 -> LLM -> 答案`

而是：

```text
用户问题
  -> 规划研究大纲
  -> 搜索资料
  -> 数据分析
  -> 生成图表
  -> 撰写报告
  -> 审核报告
  -> 必要时补充搜索/修订
  -> 最终报告
```

每个阶段都由不同 Agent 负责：

```text
ChiefArchitect  规划
DeepScout       搜索
DataAnalyst     数据分析
CodeWizard      图表/代码
LeadWriter      写报告
CriticMaster    审核
```

而这就是软件工程中经典的： `状态机`，我们写代码最开始学习的基础就是这个理念，像 if while 等，都是基础的状态机。

不过随着代码逻辑的复杂，if 判断容易隐藏具体业务逻辑，所以`有向图`这个数据结构就排上了用场。

在当前语境下，agent 的任务状态机，就对应 状态图编排能力，agent不是一次 LLM 调用，也不是简单的线性问答，而是一个多阶段、多 Agent、可循环、可分支、共享状态的研究流程。

如果没有状态图，流程会很快变成一堆难维护的 if/else + while + state["phase"]


### 1.2. 多Agent共享状态

项目中拆分的多Agent并不是各干各的，它们要共享：

```text
query
outline
facts
data_points
charts
final_report
references
critic_feedback
quality_score
iteration
phase
```

例如：

- `ChiefArchitect` 生成 `outline`
- `DeepScout` 根据 `outline` 搜索，写入 `facts`
- `DataAnalyst` 基于 `facts` 提取数据点
- `CodeWizard` 基于数据生成图表
- `LeadWriter` 基于 facts/charts/references 写报告
- `CriticMaster` 审核报告，写入 `critic_feedback`

所以需要一个统一的 `State`，在编排过程中流动。`状态图编排的价值，就是让“哪个节点读写这个状态、下一步去哪”变得清楚。`

### 1.3. 工作流循环执行

这是最关键的。

例如在审核阶段可能发现：

```text
资料不够
引用缺失
逻辑有问题
数据过旧
报告不完整
```

这时不能直接结束，而要回头：

```text
review -> revise -> review
```

或者更复杂：

```text
review -> re_researching -> writing -> review
```

这就是 LangGraph 这类状态图工具擅长表达的东西：**节点、边、条件边、循环边**。

如果传统写法，不用状态图也能写，但会变成：

```python
while iteration < max_iterations:
    critic.process(state)
    if state["phase"] == "completed":
        break
    elif state["phase"] == "re_researching":
        scout.process(state)
        writer.process(state)
    elif state["phase"] == "revising":
        writer.process(state)
```

功能一样可以实现，但是`任务的流程结构藏在代码细节里；状态图却能把流程显式表达出来`。

### 1.4. LLM的“白屏问题”

同时这么多流程在跑，时间很久，`用户感知变久，但是无可奈何`，我称之为 LLM 时代的“白屏问题”。

前面我们设计了很多工作流，这些交互需要可解释、可维护！！！

而且 LLM 时代，客户随着天马行空的想象增多，有可能Agent 很容易变复杂。后续可能加：

```text
本地知识库检索
联网搜索
招投标数据分析
政策文档分析
人类审核
后台批处理
中断恢复
不同模型分配
不同策略切换
```

如果没有状态图，新增一个阶段就要到处改调度代码。

有状态图后，可以更清楚地描述：

```text
节点是什么
输入输出是什么
成功后去哪
失败后去哪
审核不通过去哪
达到最大轮次去哪
```
这对后续维护很重要，而且研究过程必须做到可视化：

```text
planning
researching
analyzing
writing
reviewing
revising
```

状态图天然可以映射成前端时间线、流程图、日志和检查点。

比如：

```text
当前执行到哪个节点？
为什么从 review 回到了 revise？
为什么进入 re_researching？
哪一轮审核通过了？
```

这些问题，用状态图表达会比散落的函数调用更容易解释。

### 1.5.控制任务进度

这么多阶段的研究流程，用户可能中途暂停，或者网络断开，或者服务器重启，需要暂停/恢复/继续。

如何做到真正可靠的恢复，需要知道：

```text
当前 phase 是什么
上一个完成节点是什么
下一个应该执行哪个节点
当前 iteration 是第几轮
哪些状态已经生成
哪些节点不能重复跑
```

这些本质上也是状态机问题。

所以状态图编排能力能为后续做：

```text
暂停
恢复
重试
跳过
回滚
人工介入
```

打基础。

## 2. 为什么要自定义？
既然已经有了现成的调度器，为什么还要自己实现调度器呢？

因为langgraph 的状态图解决了“流程结构、共享状态、任务控制”：
可能你会想到通过类似`_build_langgraph()` 的逻辑构建：

```text
StateGraph(ResearchState)
  add_node("plan", _plan_node)
  add_node("research", _research_node)
  add_node("analyze", _analyze_node)
  add_node("write", _write_node)
  add_node("review", _review_node)
  add_node("revise", _revise_node)
  add_conditional_edges("review", _should_revise, {"revise": "revise", "complete": END})
  add_edge("revise", "review")
```

这个图能表达审核后修订再回到审核的循环。但客户要的不是“节点结束后拿到一次状态”，而是：

- 搜索过程中实时返回搜索进度、来源和事实。
- 分析过程中实时返回数据点、知识图谱和图表。
- 写作过程中实时返回阶段状态和报告片段。
- 用户点击取消后，当前 Agent 尽快停止。
- 每个阶段结束后保存检查点，并同步前端恢复所需 UI 状态。

客户需要看到每个阶段的进度，让他们知道系统还在分析中，而不是“白屏”等待⌛️。

而使用`_run_with_langgraph()` 当前只能在 `self.graph.astream(state)` 产出节点状态时，从 `node_state["messages"]` 里取新增消息。对于长耗时 Agent，这会让用户感受白屏延迟。


所以我设计的编排的架构是：

- LangGraph / 状态图：表达工作流骨架，作为兼容逻辑
- 自定义调度器：负责实时 SSE、取消、检查点、UI 状态同步，在 Agent 任务还没结束时就持续读队列并 `yield`

## 3. 🤔如何实现

架构上参考 langgraph 实现，首先就是要用`while`、`if/else`、共享 `state` 实现“回头循环调用”。

这里技术上有所取舍：
- 选取了业务上客户希望的节点实时输出，每个 Agent 执行过程中要不断从 `asyncio.Queue` 推消息，而不是LangGraph 的“一个节点执行完才会进入下一个节点”
- 舍弃了图编排的简洁抽象，使用 `while+yield+agent流式抽象+枚举状态` 模拟任务调度，每个节点执行完后，再进入下一个节点


```python
while state["iteration"] < state["max_iterations"]:
    ...
    async for msg in run_agent_with_streaming(self.critic):
        yield msg

    if state["phase"] == ResearchPhase.RE_RESEARCHING.value:
        async for msg in run_agent_with_streaming(self.scout):
            yield msg
        state["phase"] = ResearchPhase.WRITING.value
        async for msg in run_agent_with_streaming(self.writer):
            yield msg

    elif state["phase"] == ResearchPhase.REVISING.value:
        async for msg in run_agent_with_streaming(self.writer):
            yield msg
```

宏观来看架构的话：
{{< mermaid >}}
flowchart TB
  UI["Frontend"] --> Router["ResearchRouter.stream_research"]
  Router --> Response["StreamingResponse"]
  Response --> Service["DeepResearchV2Service.research"]
  Service --> GraphRun["DeepResearchGraph.run"]
  GraphRun --> Scheduler["_run_simplified(state)"]

  Scheduler --> State["ResearchState\n全局工作记忆"]
  Scheduler --> Queue["asyncio.Queue\nstate['_message_queue']"]
  Scheduler --> Checkpoint["checkpoint_service\n保存后端状态和 UI 状态"]
  Scheduler --> Cancel["Redis cancel flag\nis_research_cancelled"]

  Scheduler --> Agents["ChiefArchitect / DeepScout / DataAnalyst\nCodeWizard / LeadWriter / CriticMaster"]
  Agents --> AddMessage["BaseAgent.add_message"]
  AddMessage --> StateMessages["state['messages']"]
  AddMessage --> Queue

  Queue --> Scheduler
  Scheduler --> Service
  Service --> Response
  Response --> UI
{{< /mermaid >}}

核心调用链是：
核心调用链如下：

```text
ResearchRouter.stream_research
  -> DeepResearchV2Service.research
    -> DeepResearchGraph.run
      -> _run_simplified
        -> run_agent_with_streaming
          -> asyncio.create_task(agent.process(state))
          -> BaseAgent.add_message
          -> asyncio.Queue
    -> DeepResearchV2Service._format_sse
  -> StreamingResponse
```
没有 LangGraph 时，项目靠 自定义调度器 + 共享 ResearchState + asyncio.Queue + Redis 取消标记 + 数据库检查点 来实现这些能力。

接下来重点解释几个关键点的实现：

### 3.1 共享状态和消息队列

```python
# 主函数
async def _run_simplified(self, state: ResearchState):
    ...
```

这里的`ResearchState` 是所有 Agent 共享的全局工作记忆，保存用户问题、会话、当前阶段、迭代次数、大纲、事实库、数据点、图表、报告、参考文献、审核反馈、质量分和运行消息，以下代码只记录数据结构定义，不涉及业务代码传播🤐：

```python
class ResearchState(TypedDict):
    """
    LangGraph 状态定义

    这是整个研究过程的全局状态，所有Agent都在读写这个状态。
    """
    # 基础信息
    query: str                              # 用户原始问题
    session_id: str                         # 会话ID
    phase: str                              # 当前阶段
    iteration: int                          # 当前迭代轮次
    max_iterations: int                     # 最大迭代次数

    # 搜索模式配置
    search_web: bool                        # 是否启用网络搜索
    search_local: bool                      # 是否启用本地知识库搜索

    # 规划输出
    outline: List[Dict[str, Any]]           # 动态大纲 (Section序列化)
    mind_map: Dict[str, Any]                # 知识图谱/思维导图
    key_entities: List[str]                 # 关键实体
    research_questions: List[str]           # 待研究的子问题
    hypotheses: List[Dict[str, Any]]        # 研究假设（假设驱动研究）
    knowledge_graph: Dict[str, Any]         # 知识图谱 {nodes: [], edges: []}

    # 知识库
    facts: List[Dict[str, Any]]             # 结构化事实库
    data_points: List[Dict[str, Any]]       # 数据点
    raw_sources: List[Dict[str, Any]]       # 原始来源（网页内容）

    # 分析输出
    charts: List[Dict[str, Any]]            # 生成的图表
    code_executions: List[Dict[str, Any]]   # 代码执行记录
    insights: List[str]                     # 数据洞察

    # 写作输出
    draft_sections: Dict[str, str]          # 章节草稿 {section_id: content}
    final_report: str                       # 最终报告
    references: List[Dict[str, Any]]        # 参考文献

    # 审核反馈
    critic_feedback: List[Dict[str, Any]]   # 评论家反馈
    unresolved_issues: int                  # 未解决问题数
    quality_score: float                    # 质量评分
    pending_search_queries: List[str]       # 待执行的补充搜索查询（审核后需要补充的）

    # 元数据
    logs: List[Dict[str, Any]]              # 执行日志
    errors: List[str]                       # 错误记录
    messages: List[Dict[str, Any]]          # Agent间消息（用于流式输出）


def create_initial_state(
    query: str,
    session_id: str,
    search_web: bool = True,
    search_local: bool = False
) -> ResearchState:
    """创建初始状态

    Args:
        query: 用户查询
        session_id: 会话ID
        search_web: 是否启用网络搜索（默认True）
        search_local: 是否启用本地知识库搜索（默认False）
    """
    ...

def section_to_dict(section: Section) -> Dict[str, Any]:
    """Section 序列化"""
    ...

def fact_to_dict(fact: Fact) -> Dict[str, Any]:
    """Fact 序列化"""
    ...

class ResearchPhase(str, Enum):
    """研究阶段状态机"""
    INIT = "init"                    # 初始化
    PLANNING = "planning"            # 规划阶段
    RESEARCHING = "researching"      # 深度探索阶段
    ANALYZING = "analyzing"          # 数据分析阶段
    WRITING = "writing"              # 撰写阶段
    REVIEWING = "reviewing"          # 对抗审核阶段
    RE_RESEARCHING = "re_researching"  # 补充搜索阶段（审核发现缺失信息后）
    REVISING = "revising"            # 修订阶段（仅文字修改）
    COMPLETED = "completed"          # 完成


@dataclass
class Section:
    """报告章节"""
    id: str
    title: str
    description: str
    section_type: Literal["qualitative", "quantitative", "mixed"]  # 定性/定量/混合
    status: Literal["pending", "researching", "drafted", "reviewed", "final"]
    content: str = ""
    sources: List[str] = field(default_factory=list)
    subsections: List['Section'] = field(default_factory=list)
    requires_data: bool = False
    requires_chart: bool = False


@dataclass
class Fact:
    """结构化事实"""
    id: str
    content: str
    source_url: str
    source_name: str
    source_type: Literal["official", "academic", "news", "report", "self_media"]  # 来源类型
    credibility_score: float  # 可信度评分 0-1
    extracted_at: datetime
    related_sections: List[str] = field(default_factory=list)  # 关联章节ID
    verified: bool = False
    metadata: Dict[str, Any] = field(default_factory=dict)


@dataclass
class DataPoint:
    """数据点"""
    id: str
    name: str
    value: Any
    unit: str
    year: Optional[int]
    source: str
    confidence: float


@dataclass
class Chart:
    """图表配置"""
    id: str
    title: str
    chart_type: Literal["line", "bar", "pie", "scatter", "table", "heatmap"]
    data: Dict[str, Any]
    code: str  # 生成图表的Python代码
    image_path: Optional[str] = None
    section_id: Optional[str] = None


@dataclass
class CriticFeedback:
    """评论家反馈"""
    id: str
    target_section: str
    issue_type: Literal["missing_source", "logic_error", "bias", "hallucination", "outdated", "incomplete"]
    severity: Literal["critical", "major", "minor"]
    description: str
    suggestion: str
    resolved: bool = False


@dataclass
class AgentLog:
    """Agent执行日志"""
    timestamp: datetime
    agent: str
    action: str
    input_summary: str
    output_summary: str
    duration_ms: int
    tokens_used: int = 0
```

调度器创建初始状态：
```python
state = create_initial_state(query, session_id)
```

然后每个 Agent 都拿同一个 state：

```python
await self.planner.process(state)
await self.deep_scout.process(state)
await self.architect.process(state)
await self.scout.process(state)
await self.data_analyst.process(state)
await self.wizard.process(state)
await self.writer.process(state)
await self.critic.process(state)
```

所以不是每个 Agent 各自维护状态，而是：
```
ChiefArchitect 写 outline
DeepScout 读 outline，写 facts/references
DataAnalyst 读 facts，写 data_points/charts/knowledge_graph
LeadWriter 读 facts/charts/references，写 final_report
CriticMaster 读 final_report，写 critic_feedback/quality_score/phase
```

共享状态靠的是 同一个 Python dict 在多个 Agent 之间传递和修改。

***
那实时事件怎么实现？

调度器会在运行时注入一个异步队列：
```python
state["_message_queue"] = asyncio.Queue()
message_queue = asyncio.Queue()
```

Agent 调用 `BaseAgent.add_message(state, event_type, content)`。这个方法做两件事：

```python
def add_message(state, event_type, content):
    ...
    """添加消息到消息队列"""
    message = {"type": event_type, "content": content}
    state["messages"].append(message)
    if "_message_queue" in state:
        state["_message_queue"].put_nowait(message)
    ...
```     
1. 把事件追加到 state["messages"]
2. 如果 state["_message_queue"] 存在，则 put_nowait(message)


通过这个异步消息队列，就解耦了 agent 和 前端的 SSE 输出：
- Agent 只负责把消息放到队列里，只依赖共享状态，不需要耦合 FastAPI、StreamingResponse 或前端协议
- 调度器负责把队列里的事件转成 SSE 输出。

完整的事件流：
```
Agent
  -> add_message()
  -> 写入 state["messages"]
  -> 推入 asyncio.Queue
  -> 调度器从 Queue 读取
  -> yield 给 SSE
  -> 前端实时展示
```

###  3.2 单个 Agent 的调度逻辑

它是整个实时调度器的核心,通过抽象的 `run_agent_with_streaming(agent)`来组织任务调度

{{< mermaid >}}
flowchart TD
  Start["准备执行 Agent"] --> CancelBefore{"开始前已取消?"}
  CancelBefore -- 是 --> Stop["返回，不再执行该 Agent"]
  CancelBefore -- 否 --> CreateTask["asyncio.create_task(agent.process(state))"]
  CreateTask --> Loop{"task.done() ?"}
  Loop -- 否 --> CancelDuring{"执行中已取消?"}
  CancelDuring -- 是 --> CancelTask["task.cancel() 并等待取消完成"]
  CancelTask --> Stop
  CancelDuring -- 否 --> ReadQueue["wait_for(queue.get(), timeout=0.5)"]
  ReadQueue --> GotMsg{"读到事件?"}
  GotMsg -- 是 --> YieldMsg["yield msg 给上层 SSE"]
  YieldMsg --> Loop
  GotMsg -- 超时 --> Loop
  Loop -- 是 --> AwaitTask["await task 获取异常"]
  AwaitTask --> Drain["drain queue\n输出剩余事件"]
  Drain --> Done["Agent 阶段完成"]
{{< /mermaid >}}

其中有几个关键点：

调度器不是直接 `await agent.process(state)`，而是把 Agent 包成异步任务，后台运行：
```python
task = asyncio.create_task(agent.process(state))
```

然后一边等 Agent 跑，一边读队列：

```python
while not task.done():
    msg = await asyncio.wait_for(message_queue.get(), timeout=0.5)
    # 让调度器最多等待 0.5 秒，然后回到循环检查取消状态。
    yield msg
```

这样 Agent 在后台跑，调度器可以同时做三件事：
1. 持续读取 Agent 发出的事件
2. 检查用户是否取消：如果取消标志出现，调度器取消当前 task，并提前结束当前研究流程。
3. Agent 完成后清空剩余队列消息—drain queue

这样的话，能能做到：Agent 执行中 -> 持续产出事件 -> 前端实时看到过程


### 3.3 任务中断/取消

有了前两节的基础，就可以来搞任务的中断/取消啦:
前端点击停止时，会调用：
`POST /research/cancel/{session_id}`
后端在：
写 Redis 取消标记：
`cache.set(f"research:cancel:{session_id}", {"cancelled": True}, expire=300)`
调度器执行每个 Agent 时会反复检查：
`is_research_cancelled(session_id)`
如果发现取消：
`task.cancel()`
就会停止当前 Agent 的执行，调度器结束流程。

完整的逻辑实现是：
```python
前端点击停止
  -> POST /research/cancel/{session_id}
  -> Redis 写 cancel flag
  -> 调度器每 0.5 秒检查
  -> 发现 cancelled
  -> task.cancel()
  -> 当前 Agent 被取消
  -> 调度器结束流程
```

这样的话，我们就靠着Redis cancel flag + asyncio task.cancel()，实现了类似 langgraph 的 checkpointer 机制。

### 3.4 检查点/恢复
上面能取消任务了，那么我们怎么恢复呢？说到恢复，就必须要有 checkpoint 点，通过它来恢复。


调度器在每个大阶段结束后保存检查点。
例如 `planning` 结束后：
```python
save_checkpoint_async({
    "type": "planning",
    "status": "completed",
    "stats": {...}
})
```

保存内容包括两类：
1. 后端状态state_json, 也就是当前的ResearchState：
```text
phase
iteration
outline
facts
charts
final_report
references
critic_feedback
...
```

2. 前端 UI 状态ui_state_json,包括：
```text
research_steps
search_results
charts
knowledge_graph
streaming_report
references
```

保存逻辑：
```python
def save_checkpoint(
        self,
        session_id: str,
        state: Dict[str, Any],
        user_id: Optional[str] = None,
        ui_state: Optional[Dict[str, Any]] = None,
        final_report: Optional[str] = None,
        db: Optional[Session] = None
    ) -> Optional[str]:
        """
        保存检查点

        Args:
            session_id: 研究会话 ID
            state: ResearchState 字典（后端状态）
            user_id: 用户 ID（可选）
            ui_state: 前端 UI 状态（研究步骤、搜索结果、图表等）
            final_report: 最终报告内容

        Returns:
            检查点 ID，失败返回 None
        """
        try:
            # 提取关键信息
            query = state.get("query", "")
            phase = state.get("phase", "planning")
            iteration = state.get("iteration", 0)

            # 清理 state 中不可序列化的内容
            ...
            # 查找现有检查点
            ...

            if existing:
                # 更新现有检查点
                ...
                existing.status = "running"
                ...
            else:
                # 创建新检查点
                checkpoint = ResearchCheckpoint(
                    session_id=session_id,
                    user_id=UUID(user_id) if user_id else None,
                    query=query,
                    phase=phase,
                    iteration=iteration,
                    state_json=clean_state,
                    ui_state_json=clean_ui_state,
                    final_report=final_report,
                    status="running",
                )
                db.add(checkpoint)
                db.flush()
                checkpoint_id = str(checkpoint.id)

            db.commit()
            # 详细日志
            ...
            return checkpoint_id

        except Exception as e:
            logger.error(f"Failed to save checkpoint: {e}")
            db.rollback()
            return None
```
***
需要恢复的时候，这里要注意，要区分两种情况：

```text
1. GET /research/checkpoint/{session_id}/full
   恢复前端 UI 展示

2. POST /research/resume/{session_id}
   恢复后端研究执行
```

当前前端在进入聊天页面时，会自动调用：

```text
GET /research/checkpoint/{session_id}/full
```

把之前已经产生的研究过程的 UI 状态回显，比如：

```text
研究步骤
搜索结果
图表
知识图谱
已生成的报告片段
引用
```

它不会继续跑 Agent，也不会重新开始搜索。它只是读取数据库里的 checkpoint：

```text
research_checkpoints.state_json
research_checkpoints.ui_state_json
research_checkpoints.final_report
```

然后前端把 UI 还原出来。

所以它解决的是：

```text
用户刷新页面 / 重新进入会话
还能看到之前的研究过程
```

它是“读状态”。

2. `POST /resume` 是“继续后端任务”

这个接口是让后端继续执行研究流程。

它会调用：

```python
service_v2.research(..., resume=True)
```

然后后端执行：

```python
state = self._load_checkpoint(session_id)
```

也就是把上次保存的后端 `ResearchState` 加载回来，再进入研究流程。

所以它解决的是：

```text
后端任务中断后，希望继续跑
```

它是“继续执行”。

千万不能设计成只用一个接口，这是我一开始犯的🙅，和领导讨论的过程中，他及时发现了问题：
- 如果页面一打开就调用 `/resume`

那会有问题：

```text
用户只是想看看历史结果
但后端又开始继续跑 Agent
又开始消耗模型 token
又可能重新搜索
又会改变 checkpoint
```
这不合理。

所以页面加载时只能调用只读接口：

```text
GET /checkpoint/full
```

- 如果只调用 `/checkpoint/full`

也有问题：
```text
前端只能恢复显示
后端不会继续执行
```

所以当用户明确点击“继续研究”时，才应该调用：

```text
POST /resume/{session_id}
```

所以，正确逻辑实现应该是这样

1. 场景 A：用户刷新页面

```text
前端进入 /chat/{session_id}
  -> GET /research/checkpoint/{session_id}/full
  -> 后端返回 checkpoint
  -> 前端恢复研究步骤、搜索结果、图表、报告
  -> 不继续执行任务
```

这个时候只是恢复 UI。

2. 场景 B：用户点击“继续研究”

```text
用户点击继续研究
  -> POST /research/resume/{session_id}
  -> 后端加载 state_json
  -> 后端继续执行 Agent 流程
  -> 后端通过 SSE 持续返回新事件
  -> 前端继续更新研究过程 UI
```

这个时候才继续执行。

***
#### 3.4.1 待优化
不过这个实现还是有待优化：这种恢复的逻辑设计不是“精确断点续跑”，这个版本能做到：

```text
取消任务
保存阶段级检查点
恢复前端 UI
加载后端 state
```

但还没完全做到：

```text
从中断的具体 Agent/具体 phase 精确继续
```

因为 `_run_simplified()` 当前加载 checkpoint 后，还是按设计好的固定流程（具体过程见下一节）执行：

```text
Plan -> Research -> Analyze -> Write -> Review...
```

它没有根据 checkpoint 里的 `phase` 或 `completed_steps` 跳过已完成阶段。

所以现在的恢复更接近：

```text
加载旧状态，重新进入流程
```

而不是：

```text
从上次中断点继续执行下一个节点
```

要做到真正恢复，需要再补：

```text
completed_steps
next_step
paused status
phase-aware scheduler
```

例如：

```text
checkpoint.phase == "analyzing"
completed_steps = ["planning", "researching"]
next_step = "analyzing"
```

恢复时调度器应该跳过 planning/researching，直接从 analyzing 继续。

`这个先记录下来了，后面再优化`，因为还有其他东西要🧐，真让人头大啊。

目前这套自定义的调度器架构，已经能解决：
```text
共享状态：
  ResearchState dict 在所有 Agent 之间传递

实时事件：
  state["_message_queue"] + BaseAgent.add_message()

任务控制：
  asyncio.create_task(agent.process(state))

取消：
  Redis cancel flag + task.cancel()

检查点：
  CheckpointService 保存 state_json + ui_state_json

恢复展示：
  前端加载 full checkpoint 恢复 UI

继续执行：
  后端已有 resume 雏形，但还不是严格断点的精准续跑
```

### 3.5 工作流的前置阶段

主流程设计的固定前置阶段是：`planning -> researching -> analyzing -> writing`

对应执行顺序：

```text
ChiefArchitect
DeepScout
DataAnalyst
CodeWizard
LeadWriter
```

每个阶段开始前，调度器先 `yield {"type": "phase", ...}` 通知前端切换阶段，再设置 `state["phase"]`，然后调用 `run_agent_with_streaming(agent)`。阶段结束后会：

```text
1. 清空 state["messages"]
2. update_ui_state()
3. save_checkpoint_async(step_info)
4. yield checkpoint_saved 事件
```

`update_ui_state()` 会从后端状态提取前端恢复需要的数据，包括：

- `research_steps`
- `search_results`
- `charts`
- `knowledge_graph`
- `streaming_report`
- `references`

这样即使用户刷新页面或恢复会话，也可以通过检查点拿到后端状态和 UI 展示状态。

### 3.6 工作流的审核

固定阶段结束后进入审核循环。循环条件是：`state["iteration"] < state["max_iterations"]`

每一轮先执行 `CriticMaster`。`CriticMaster` 根据报告质量和问题类型修改 `state["phase"]`。调度器再根据 `state["phase"]` 分流。

![](/agents/plan.png)

审核有三条主要分支：

- `COMPLETED`：审核通过或达到完成条件，退出循环。
- `RE_RESEARCHING`：审核发现缺少信息，需要回到 `DeepScout` 补充搜索，再进入 `LeadWriter` 重写，之后回到审核。
- `REVISING`：审核认为不需要新搜索，只需要 `LeadWriter` 根据反馈修订文字，之后回到审核。

上面这套工作流，这就是当前不依赖 LangGraph 也能循环和回头调用的原因：循环逻辑由普通 `while` 加 `state["phase"]` 分支完成，状态仍然集中保存在 `ResearchState` 中。

### 3.7 前后端SSE交互时序
基于上面的架构设计，前后端使用 SSE 的交互数据格式，也就清楚了：

![](/agents/sse.png)

## 4. 与 LangGraph 版本的差异

| 维度 | 保留的 LangGraph 路径 | 当前手写调度器 |
| --- | --- | --- |
| 流程表达 | 声明式状态图 | Python 顺序流程 + while 分支 |
| 循环回跳 | `review -> revise -> review` | `reviewing -> re_researching/revising -> reviewing` |
| 事件输出 | 读取节点状态中的 `messages` | Agent 执行中实时读取 `asyncio.Queue` |
| 分析阶段 | 图定义逻辑表达 | 抽象单 agent 逻辑组合 |
| 补充搜索 | 图定义逻辑表达 `RE_RESEARCHING` | 审核后可回到 `DeepScout` 补充搜索 |
| 取消 | 节点执行逻辑、运行时wrapper控制层| 每 0.5 秒检查取消标志并取消 task |
| 检查点/UI 恢复 | 传入 thread_id，checkpointer机制控制 | 每阶段保存后端状态和 UI 状态 |

当前自定义调度器，并不是替代了 LangGraph 的“循环能力”，而是补上了本次客户需要的更细的表达能力。

## 5.实际效果

当前设计带来的效果：
![](/agents/2.png)
![](/agents/3.png)
![](/agents/5.png)
![](/agents/7.png)


- 前端能看到研究过程，而不是只等每个阶段的结果和最终报告。
- 搜索、分析、图表、审核等长耗时阶段可以持续推送进展。
- 用户取消研究时，当前 Agent 可以被调度器取消。
- 每个阶段结束后都会保存检查点，支持后续恢复。
- 审核发现问题后，可以回头补充搜索或修订报告。
- Agent 与 SSE 框架解耦，Agent 只负责写共享状态和发送领域事件。

当然，这套架构也有个明显的缺点是：流程逻辑分散在 Python 调度代码中，不如 LangGraph 图直观。后续如果要重新切回 LangGraph，需要补齐节点内部实时事件流、补充搜索分支、取消和检查点这些运行时能力。

目前已经预留了口子，后期通过策略模式，进行动态切换

- 当前执行策略由 `ExecutionStrategySelector` 集中选择：`auto/queue` 使用 `QueueStreamingStrategy`
- `langgraph` 在图可用时使用 `LangGraphStrategy`，`hybrid` 暂时降级到 queue。

如果后面继续优化，到时候在记录吧，今天就先到这了👋🏻