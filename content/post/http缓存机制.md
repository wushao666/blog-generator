---
title: "Http缓存机制"
date: 2022-09-27T15:12:54+08:00
draft: false

tags: ["http"]
categories: ["web世界"]

contentCopyright: MIT
mathjax: true
autoCollapseToc: true
---

> 今天来记录一下浏览器的缓存机制。
## 缓存
缓存是在web开发中经常用到的一种技术，有很多的应用场景，今天主要聊聊http请求的缓存。

## 设计缓存机制
web应用中，http请求对网络带宽有一定的要求，我们为了性能考虑，应该合理发送网络请求，那么为了减少一些网络请求，http设计了一套缓存机制。
怎么设计呢，首先能想到：
- 我们可以使用本地文件缓存+时间
那么到期后，再去请求，文件是否真正的更新了呢，需要：
- 更新机制
也就是两种缓存策略`强缓存、协商缓存`。
### 强缓存
也有人叫做一级缓存，当我们请求网络资源时，服务器返回资源的同时会在响应头里面加上两个字段`expires或者cache-control`，这两个字段可能有一个，也可能都有，两者都存在时，`cache-control`优先级更高
- `Expires: Wed, 21 Oct 2015 07:28:00 GMT`，使用GMT绝对时间来处理，在这个时间只能访问本地缓存文件，不发送网络请求。
它有一个明显的弊端，如果本地时间出了问题，就有可能不准确。
- `Cache-Control: max-age=200`，使用相对时间，200秒内访问本地缓存文件，200秒后再去发送网络请求。
它的值相对多一些，常见的有：
- Cache-Control:public，如果有多个服务节点，每个节点都可以缓存
- Cache-Control:private，如果有多个服务节点，中间节点不可以缓存
- Cache-Control:no-cache, max-age=0, must-revalidate，这三个值客户端可以缓存资源，每次使用缓存资源前都必须重新验证其有效性。这意味着每次都会发起 HTTP 请求，但当缓存内容仍有效时可以跳过 HTTP 响应体的下载，不再使用max-age，需要配合使用ETag/If-none-match和Last-modified/If-modified-since两对协商缓存使用。
- Cache-Control:no-store，真的不适用缓存哦
### 协商缓存
当我们的本地缓存资源过期后，需要重新发送网络请求获取资源，有可能资源并没有过期，这个时候需要一种更新机制保证。
此时我们发送新的网络请求时，服务端会通过两对响应头**ETag/If-none-match和Last-modified/If-modified-since两对header**来管理协商缓存。
- 发送请求时获取本地资源的ETag: "deadbeef"值，通过If-None-Match: "deadbeef"发送到服务器端，服务端匹配一下这个值是否更改，如果没有更新，则返回304，更新了则返回新的ETag响应头和200状态码，但随着分布式的发展，有可能文件确实没更新，但是ETag值变了，所以需要另一对header来配合。
- 发送请求时获取本地资源的Last-Modified: Tue, 22 Feb 2022 22:00:00 GMT，通过If-Modified-Since: Tue, 22 Feb 2022 20:20:20 GMT发送到服务器端，服务端匹配一下这个值是否更改，如果没有更新，则返回304，更新了则返回新的ETag响应头和200状态码，但是只要是绝对时间，就有可能有问题，反过来也需要ETag和If-None-Match配合使用。
所以现代web开发中，这两者一般同时开启，保证缓存+有效更新。
