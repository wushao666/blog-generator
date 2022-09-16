---
title: "手写goweb框架02-路由实现"
date: 2022-09-16T16:58:00+08:00
draft: false

tags: ["go"]
categories: ["web世界"]

contentCopyright: MIT
mathjax: true
autoCollapseToc: true
---

> 本节我们来实现框架的基础路由部分，我们会按照5步循序渐进的实现这个路由。

## go原生实现基础路由
go的http包很强大，可以直接实现基础路由做测试用。
```go
package main

import (
	"fmt"
	"log"
	"net/http"
)

func main() {
	http.HandleFunc("/hello", func(writer http.ResponseWriter, request *http.Request) {
		fmt.Fprintln(writer, "hello 我们用原生go实现了一个接口")
	})
	err := http.ListenAndServe(":8111", nil)
	if err != nil {
		log.Fatal(err)
	}
}
```
以上的代码就实现了一个web接口，开启8111端口，可以直接访问`localhost:8111/hello`，页面会输出`hello 我们用原生go实现了一个接口`。
很明显当我们要实现n多接口时，要写很多模版语法，重复操作很多。

## 1. 最简单的路由实现
为了实现路由，我们需要
1. 首先抽象一个`router结构体`，具备一个`handlerMap`的map存储不同的http.HandleFunc，那这个结构体还要具备什么功能呢，它需要能够添加不同的路由，也就是基本的Add 功能做指针接收器，实现添加`http.HandleFunc`。
2. 这个server.go提供一个New函数，暴露一个路由引擎，改引擎具有一个Run的指针接收器，实现`http.ListenAndServe`。
简约的server.go代码如下所示：
```go
package xxx

import (
	"log"
	"net/http"
)

type HandleFunc func(w http.ResponseWriter, r *http.Request)
type router struct {
	handleFuncMap map[string]HandleFunc
}

func (r *router) Add(name string, handleFunc HandleFunc) {
	r.handleFuncMap[name] = handleFunc
}

type Engine struct {
	router
}

func New() *Engine {
	return &Engine{
		router: router{handleFuncMap: map[string]HandleFunc{}},
	}
}

func (e *Engine) Run() {
	for key, value := range e.handleFuncMap {
		http.HandleFunc(key, value)
	}

	err := http.ListenAndServe(":8111", nil)
	if err != nil {
		log.Fatal(err)
	}

}
```
在我们的main.go里面，我们可以这么使用：
```go
 //2. 使用手写框架实现
	engine := xxx.New()
	engine.Add("/hello", func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprintf(w, "%s 欢迎来到手写web框架", "wushao")
	})

	engine.Run()
```
这时候，我们在页面上就可以正常访问`localhost:8111/hello`了，用这种方式，我们应用层只需要不断注册路由，实现自己的handler中的业务逻辑就行，相对第一节省略了一些重复操作。

但是，我们真实业务中，路由肯定是要分组的，也就是一类路由有统一的前缀，目的是为了保证写的接口归属于某一个模块，这样便于管理以及维护，代码也更为清晰，比如：`/user/getUser` `/user/createUser` 都同属于user模块

## 2. 实现分组路由
为了实现分组路由，我们需要:
1. 引入新的结构体`routerGroup`，做分组用，我们再想一下，原来的handleFuncMap、Add的指针接收器也要归属于`routerGroup`，通过组来实现用来路由的功能，比如`/user`组下添加具体的`/getUser /createUser`，实现不同的接口。
2. 原来的router结构体，需要`routerGroups`切片来存储不同的routerGroup，它需要一个Group的指针接收器，来实现分组的功能
3. 原来的Run函数，就需要双层遍历了，先遍历组，再遍历组里面不同的handleFunc实现
改造server.go代码如下：
```go

type HandleFunc func(w http.ResponseWriter, r *http.Request)

// 路由组
type routerGroup struct {
	name          string
	handleFuncMap map[string]HandleFunc
}

func (r *routerGroup) Add(name string, handleFunc HandleFunc) {
	r.handleFuncMap[name] = handleFunc
}

// 3、user /get/list user组下面才是url
//路由表 由路由组组成
type router struct {
	routerGroups []*routerGroup
}

func (r *router) Group(name string) *routerGroup {
	group := &routerGroup{
		//handleFuncMap: map[string]HandleFunc{},
		// 和上面的写法一个效果
		handleFuncMap: make(map[string]HandleFunc),
		name:          name,
	}

	r.routerGroups = append(r.routerGroups, group)
	return group
}

type Engine struct {
	*router //这样写的原因是啥呢
}

func New() *Engine {
	return &Engine{
		&router{},
	}
}

func (e *Engine) Run() {
	for _, group := range e.routerGroups {
		for key, value := range group.handleFuncMap {
			groupNameHasSlash := strings.HasPrefix(group.name, "/")
			routerKeyHasSlash := strings.HasPrefix(key, "/")
			var groupName string
			var handleFuncName string
			if groupNameHasSlash {
				groupName = group.name
			} else {
				groupName = "/" + group.name
			}
			if routerKeyHasSlash {
				handleFuncName = groupName + key
			} else {
				handleFuncName = groupName + "/" + key
			}

			http.HandleFunc(handleFuncName, value)
		}

	}

```
在上面的代码中我们兼容处理了用户注册url时没有写`/`的情况。
main.go使用时稍微更改一下，先注册组，在注册组下面的handleFuc
```go
//2. 使用手写框架实现
	groupUser := engine.Group("user")
	groupUser.Add("/hello", func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprintf(w, "%s 欢迎来到手写web框架", "wushao")
	})

	engine.Run()
```
这时候，我们在页面上就可以访问`localhost:8111/user/hello`了，再改造的过程中可以发现我们是一步步的向上抽象的过程，顶层现在是group。
但是，等一等，让我们回想一下[第一节课](https://vvushaolin.com/post/%E6%89%8B%E5%86%99goweb%E6%A1%86%E6%9E%B601-%E5%88%86%E6%9E%90%E6%A1%86%E6%9E%B6/#1-%E8%B7%AF%E7%94%B1)中的路由分析部分，当时我们说有`两个重点`要实现，其中第一点就是请求的方法是什么，到目前为止，我们的路由只是能访问url，但是什么类型的http请求我们无法知道。

## 3. 支持不同的请求方式
为了让我们的路由支持不同的http请求方式，我们需要继续改造我们的server.go：
1. routerGroup需要一个handlerMethodMap存储我们的组中的不同的url属于什么http方法，类似于
```go
{
  "get": ["/getUser", "/hi"],
  "post": ["/createUser"]
}
```
就是说user组下面的`/getUser`是get方法，`/createUser`是post方法，即：
```go
GET http://localhost:8111/user/getUser
POST http://localhost:8111/user/createUser
```
2. routerGroup的Add方法不再需要，因为我们现在要根据不同的请求方式来注册对应的handlerMap
3. engine引擎的**Run方法不能再简单的`http.HandleFunc`了，我们要把所有的请求全拦截`http.Handle`**，在拦截里面在做处理。
在go的net/http/server.go源码中我们可以知道http.Handle的详细签名
```go
// Handle registers the handler for the given pattern
// in the DefaultServeMux.
// The documentation for ServeMux explains how patterns are matched.
func Handle(pattern string, handler Handler) { DefaultServeMux.Handle(pattern, handler) }

```
注意其中的Handler，他是一个interface:
```go
type Handler interface {
	ServeHTTP(ResponseWriter, *Request)
}
```
所以我们要实现ServeHTTP方法，即实现了Handler接口，也就是我们的**engine引擎需要一个ServeHTTP的指针接收器**。
我们自己的server.go的对应修改如下：
```go
// 路由组
type routerGroup struct {
	name             string
	handlerFuncMap   map[string]HandleFunc
	handlerMethodMap map[string][]string
}
//去掉Add方法 添加下面的具体的请求方式的指针接收器
func (r *routerGroup) Any(name string, handlerFunc HandleFunc) {
	r.handlerFuncMap[name] = handlerFunc
	r.handlerMethodMap["Any"] = append(r.handlerMethodMap["any"], name)
}
func (r *routerGroup) Get(name string, handlerFunc HandleFunc) {
	r.handlerFuncMap[name] = handlerFunc
	r.handlerMethodMap[http.MethodGet] = append(r.handlerMethodMap[http.MethodGet], name)
}
func (r *routerGroup) Post(name string, handlerFunc HandleFunc) {
	r.handlerFuncMap[name] = handlerFunc
	r.handlerMethodMap[http.MethodPost] = append(r.handlerMethodMap[http.MethodPost], name)
}
// ... 把你需要实现的http方法都按照上面的格式加入即可
func (r *router) Group(name string) *routerGroup {
	group := &routerGroup{
		handleFuncMap: make(map[string]HandleFunc),
		name:          name,
    //初始化时一定要注意routerGroup结构体增加新属性，这里就有初始化
    handlerMethodMap: make(map[string][]string), 
	}

	r.routerGroups = append(r.routerGroups, group)
	return group
}
func (e *Engine) ServeHTTP(writer http.ResponseWriter, request *http.Request) {
	// 先拿到请求的方法类型 GET POST啥的
	method := request.Method
	groups := e.router.routerGroups
	// 根据url进行匹配
	for _, group := range groups {
		for name, methodHandle := range group.handlerFuncMap {
			groupNameHasSlash := strings.HasPrefix(group.name, "/")
			routerKeyHasSlash := strings.HasPrefix(name, "/")
			var groupName string
			var requestUrl string
			if groupNameHasSlash {
				groupName = group.name
			} else {
				groupName = "/" + group.name
			}
			if routerKeyHasSlash {
				requestUrl = groupName + name
			} else {
				requestUrl = groupName + "/" + name
			}

			//http.HandleFunc(requestUrl, methodHandle)
			// 比较请求url和拼接的url是否相同
			if request.RequestURI == requestUrl {
				// 先看看属不属于any类型的
				routers, ok := group.handlerMethodMap["Any"]
				if ok {
					for _, routerName := range routers {
						// 比较map中存储的切片中的最后一级url和name
						if routerName == name {
							methodHandle(writer, request)
							return
						}
					}
				}
				// any中不ok 就去methodMap中遍历
				routers, ok = group.handlerMethodMap[method]
				if ok {
					for _, routerName := range routers {
						// 比较map中存储的切片中的最后一级url和name
						if routerName == name {
							methodHandle(writer, request)
							return
						}
					}
				}
				// 具体method中不ok 就报错了
				writer.WriteHeader(http.StatusMethodNotAllowed)
				fmt.Fprintf(writer, "%s %s not allowed \n", request.RequestURI, method)
				return
			}

		}

	}
	// url不匹配
	writer.WriteHeader(http.StatusNotFound)
	fmt.Fprintf(writer, "%s %s not found \n", request.RequestURI, method)
}
func (e *Engine) Run() {
	// 3、支持不同的方法，全拦截
	http.Handle("/", e)
	err := http.ListenAndServe(":8111", nil)
	if err != nil {
		log.Fatal(err)
	}
}
```
我们在main.go使用时再稍微更改一下：
```go
//2. 使用手写框架实现
	engine := xxx.New()
	groupUser := engine.Group("user")
	groupUser.Get("/getUser", func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprintf(w, "%s 欢迎来到手写web框架", "wushao")
	})
	groupUser.Post("/createUser", func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprintf(w, "%s 2欢迎来到手写web框架", "wushao")
	})
	engine.Run()
```
到此为止，我们终于能够访问到下面的这种支持不同http请求方式的url了。
```go
GET http://localhost:8111/user/getUser
POST http://localhost:8111/user/createUser
```
为了实现支持不同请求方式的路由组，我们:
1. 进一步抽象了路由组的方法，按照不同http请求存储二级url
2. 并且简化了Run函数的监听，把比较重的业务逻辑放到了Handler接口的ServeHTTP方法中，在Engine的指针接收器里面实现这个方法
但是，上述的代码还存在一个问题，restful规范中是可以可以支持同一个路由使用不同的请求方式，例如
```go
GET http://localhost:8111/user/user
POST http://localhost:8111/user/user
```
按照目前的写法，我们的代码是哪个方法类型的后注册，只能访问到哪个，前一个就会被覆盖掉。

## 4. 同一路径支持不同的请求方式，引入上下文方式
为了修改第三节中遗留的问题，我们需要：
1. 继续**改造routerGroup结构体的handlerFuncMap属性**，因为目前我们无法区分出二级url的方法类型，所以我们要：
```go
handlerFuncMap   map[string]HandleFunc
// 同一路径的不同请求方式
handlerFuncMap   map[string]map[string]HandleFunc
```
这样我们的handlerFuncMap存储的结构就由：
```go
{
  "/user": HandleFunc,
}
```
变成了：
```go
{
  "/user": {
    "post": HandleFunc,
    "get": HandleFunc,
  }
}
```
2. 改造了`handlerFuncMap`后，我们势必需要**把routerGroup的方法处理函数进行修改，需要加上method字段**，同时抽象公共函数handle简化操作，并改造原来的支持不同请求方式的那些函数，简化ServeHTTP。
3. 同时提取一个上下文context的结构体，简化`type HandleFunc func(w http.ResponseWriter, r *http.Request)`中的形参
对应的我们的server.go的对应修改如下
```go
const Any = "ANY"

// HandleFunc 使用上下文结构体改造
type HandleFunc func(ctx *Context)

// 路由组
type routerGroup struct {
	name string
	// 同一路径的不同请求方式
	handlerFuncMap map[string]map[string]HandleFunc
	//支持不同的请求方式  {"post": ["/hi", "/hello"]}
	handlerMethodMap map[string][]string
}
// 增加新的统一handle方法
func (r *routerGroup) handle(name string, method string, handleFunc HandleFunc) {
	_, ok := r.handlerFuncMap[name]
	if !ok {
		r.handlerFuncMap[name] = make(map[string]HandleFunc)
	}
	_, ok = r.handlerFuncMap[name][method]
	if ok {
		panic("有重复路由")
	}
	r.handlerFuncMap[name][method] = handleFunc
	r.handlerMethodMap[method] = append(r.handlerMethodMap[method], name)

}
func (r *routerGroup) Any(name string, handlerFunc HandleFunc) {
	r.handle(name, Any, handlerFunc)
}
func (r *routerGroup) Get(name string, handlerFunc HandleFunc) {
	r.handle(name, http.MethodGet, handlerFunc)
}
func (r *routerGroup) Post(name string, handlerFunc HandleFunc) {
	r.handle(name, http.MethodPost, handlerFunc)
}

func (r *router) Group(name string) *routerGroup {
	group := &routerGroup{
    //初始化handlerFuncMap修改
		handlerFuncMap:   make(map[string]map[string]HandleFunc),
		name:             name,
		handlerMethodMap: make(map[string][]string),
	}

	r.routerGroups = append(r.routerGroups, group)
	return group
}
func (e *Engine) ServeHTTP(writer http.ResponseWriter, request *http.Request) {
	// 先拿到请求的方法类型 GET POST啥的
	method := request.Method
	groups := e.router.routerGroups
	// 根据url进行匹配
	for _, group := range groups {
		for name, methodHandle := range group.handlerFuncMap {
			groupNameHasSlash := strings.HasPrefix(group.name, "/")
			routerKeyHasSlash := strings.HasPrefix(name, "/")
			var groupName string
			var requestUrl string
			if groupNameHasSlash {
				groupName = group.name
			} else {
				groupName = "/" + group.name
			}
			if routerKeyHasSlash {
				requestUrl = groupName + name
			} else {
				requestUrl = groupName + "/" + name
			}

			//http.HandleFunc(requestUrl, methodHandle)
			// 比较请求url和拼接的url是否相同
			if request.RequestURI == requestUrl {
				//构造上下文
				ctx := &Context{
					W: writer,
					R: request,
				}
				// 先看看属不属于any类型的
				handle, ok := methodHandle[Any]
				if ok {
					handle(ctx)
					return
				}
				handle, ok = methodHandle[method]
				if ok {
					handle(ctx)
					return
				}
				// 具体method中不ok 就报错了
				writer.WriteHeader(http.StatusMethodNotAllowed)
				fmt.Fprintf(writer, "%s %s not allowed \n", request.RequestURI, method)
				return
			}

		}

	}
	// url不匹配
	writer.WriteHeader(http.StatusNotFound)
	fmt.Fprintf(writer, "%s %s not found \n", request.RequestURI, method)
}
```
经过上面的改造我们在main.go中使用就不会存在同一个url不能访问不同请求方式的问题了。
```go
  //2. 使用手写框架实现
	engine := msgo.New()
	groupUser := engine.Group("user")
	groupUser.Get("/user", func(ctx *xxx.Context) {
		fmt.Fprintf(ctx.W, "%s get 欢迎来到手写web框架", "wushao")
	})
	groupUser.Post("/user", func(ctx *xxx.Context) {
		fmt.Fprintf(ctx.W, "%s post 欢迎来到手写web框架", "wushao")
	})
```