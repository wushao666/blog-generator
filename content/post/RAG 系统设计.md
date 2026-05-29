---
title: "RAG系统设计"
date: 2023-04-14T21:53:31+08:00
draft: false
mermaid: true

tags: ["RAG"]
categories: ["AI-LLM"]

contentCopyright: MIT
mathjax: true
autoCollapseToc: true

---

{{< mermaid >}}
flowchart LR
    Client["前端/调用方"] --> API["FastAPI app_main:app"]

    API --> UserRouter["router/user_rt.py\n登录、注册、STS Token"]
    API --> ChatRouter["router/chat_rt.py\n会话、上传、解析、问答"]
    API --> HistoryRouter["router/history_rt.py\n历史、文件列表、删除"]

    UserRouter --> AuthService["service/auth.py"]
    ChatRouter --> QuickParse["service/quick_parse_service.py"]
    ChatRouter --> FileParse["service/core/file_parse.py"]
    ChatRouter --> Retrieval["service/core/retrieval.py"]
    ChatRouter --> ChatService["service/core/chat.py"]
    HistoryRouter --> DocOps["service/document_operations.py"]

    AuthService --> PG[("PostgreSQL\ngsk")]
    QuickParse --> Redis[("Redis\n临时文档内容")]
    FileParse --> ES[("Elasticsearch\n文档分片索引")]
    Retrieval --> ES
    ChatService --> Redis
    ChatService --> PG
    DocOps --> ES
    DocOps --> PG

    ChatService --> LLM["DashScope/OpenAI 兼容接口"]
    FileParse --> Embedding["DashScope Embedding"]
{{< /mermaid >}}