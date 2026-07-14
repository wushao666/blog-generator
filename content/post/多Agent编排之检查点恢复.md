---
title: "多Agent编排之重构检查点恢复"
date: 2026-03-10T00:39:00+08:00
draft: true
---

还记得上一篇文章—手写调度器，我们提到的“检查点恢复”吗？

遗留了一个[小问题](https://vvushaolin.com/post/%E5%A4%9Aagent%E7%BC%96%E6%8E%92%E4%B9%8B%E6%89%8B%E5%86%99%E8%B0%83%E5%BA%A6%E5%99%A8/#341-%E5%BE%85%E4%BC%98%E5%8C%96)：**无法从中断的具体 Agent/具体 phase 精确继续**，是按照固定的流程继续重新跑的。
今天我们就来完善一下。

## 2.1 之前咋取消的？
前端在的 `handleStop` 做了两层取消：

```ts
await readerRef.current.cancel()
await api.session.cancelResearch(currentSessionIdRef.current)
```

第一层：取消浏览器正在读取的 SSE 流。  
也就是停止前端继续消费 `/research/stream` 返回的数据。

第二层：调用后端取消接口。  
封装在`POST /research/cancel/{session_id}`

后端在接着会把取消标志写入 Redis：

```py
cache.set(f"research:cancel:{session_id}", {"cancelled": True}, expire=300)
```

然后调度器周期性检查：

```py
is_research_cancelled(session_id)
```

执行 Agent 时，每 0.5 秒左右检查一次。如果发现取消，就：

```py
task.cancel()
```
当时的取消链路是：

```tex
点击停止
  -> 前端取消 reader
  -> 前端 POST /research/cancel/{session_id}
  -> 后端 Redis 写 cancel flag
  -> 调度器检查到取消
  -> cancel 当前 Agent task
  -> 结束研究流程
```
## 2.2 **优化取消逻辑**

再回头看，是不是有点问题：当前逻辑下，前端是先 `reader.cancel()`，再调用后端取消接口。
这样用户体验上很快停止，但前端大概率收不到后端后续的 `research_cancelled` 事件，因为 SSE 读取已经被前端主动断开了。

优化后，更合理的顺序应该是是：

```text
先 POST /research/cancel/{session_id}
再 abort/cancel SSE reader
```

或者两个并行发，但 UI 直接本地标记为“已停止”。

## 2.3 之前咋恢复的？
前端的“恢复展示检查点”，在进入会话时，页面先调用：[/pages/chat/index.tsx]

```ts
api.session.getFullResearchCheckpoint(id)
```

[/api/session.ts]然后调用后端接口：

```ts
GET /research/checkpoint/{session_id}/full
```

它会恢复：

- 研究步骤 `research_steps`
- 搜索结果 `search_results`
- 图表 `charts`
- 知识图谱 `knowledge_graph`
- 已生成报告 `streaming_report`
- 引用来源 `references`

所以能够做到如下的“恢复能力“：

```text
刷新页面 / 回到会话
  -> 加载 checkpoint
  -> 恢复前端研究过程 UI
  -> 恢复已生成报告/图表/搜索结果
```

但这只是**恢复展示**，不是严格意义上的“接着上次继续执行”。

## 2.4 **优化恢复逻辑**

很明显，[/app/router/research_router.py]后端的接口：

```text
POST /research/resume/{session_id}
```
它会：

```py
service_v2.research(query=..., session_id=session_id, resume=True)
```

而 `DeepResearchGraph.run()` 也会加载 checkpoint：

```py
state = self._load_checkpoint(session_id)
```
幸好这个之前设计的逻辑，就预留了优化空间。

要想优化恢复，我们要定位清楚问题，找到了问题，其实都有办法解决.

很多时候，正是因为稀里糊涂的设计的代码，改都不知道咋改，`**AI 时代发现问题，才是更重要的能力**`。
### 2.4.1 定位问题

问题出现在工作流设计了一个固定阶段：当前 `_run_simplified()` 不是 phase-aware resume。它加载 state 后，仍然从 `Phase 1: Plan` 开始顺序跑：

```text
Plan -> Research -> Analyze -> Write -> Review...
```

所以导致现在的 resume 更像：

```text
加载旧 state，然后重新进入完整流程
```

不是纯粹的恢复：`从上次中断的 phase 后面继续`

所以要真正做到“取消后继续执行”，应该这样设计：

需要三个关键改造：

1. 取消时把 checkpoint 状态标记为 `paused`

当前 `save_checkpoint()` 默认写 `running`，完成时写 `completed`，失败时写 `failed`。取消时应该补一个：

```py
checkpoint_service.update_status(session_id, "paused")
```

并保存：

```text
phase
iteration
last_completed_step
next_step
ui_state
state_json
```

2. 调度器变成 `phase-aware resume`

`_run_simplified(state)` 不能每次都从 planning 开始。应该根据 checkpoint 里的状态决定从哪里继续：

```text
phase == planning/init       -> 从 planning 开始
phase == researching         -> 从 researching 或下一安全点开始
phase == analyzing           -> 从 analyzing 开始
phase == writing             -> 从 writing 开始
phase == reviewing           -> 从 reviewing 开始
phase == re_researching      -> 从 supplementary search 开始
phase == revising            -> 从 revising 开始
```

同时也要记录 `completed_steps`，恢复时才能够跳过已完成阶段：

```text
completed_steps = ["planning", "researching"]
next_step = "analyzing"
```

这样不会重复搜索、重复写报告。

3. 前端应该接入 resume 流

前端现在只有 `cancelResearch` 和 `getFullResearchCheckpoint`，缺少：

```ts
resumeResearch(sessionId)
```

应该重新封装：

```ts
POST /research/resume/{session_id}
Accept: text/event-stream
responseType: 'stream'
adapter: 'fetch'
```

然后 UI 上在检测到 checkpoint.status 是 `paused` 或 `running` 时，显示“继续研究”按钮。点击后复用现有 SSE 解析逻辑 `parseData()`，继续把事件写入同一套 `researchStepsRef` / `researchDetailsRef`。

重新设计后的链路：

```text
点击停止
  -> 后端取消
  -> 保存 paused checkpoint
  -> 前端展示“已暂停，可继续”

点击继续研究
  -> POST /research/resume/{session_id}
  -> 后端加载 checkpoint
  -> 调度器从 next_step 继续
  -> SSE 继续推送
  -> 前端复用原来的研究过程 UI
```


经过这次重构设计，现在才是真的“能取消、能恢复展示”✅