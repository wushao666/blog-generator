---
title: "BFF层服务的前端工程化"
date: 2024-08-26T10:35:43+08:00
draft: false

tags: ["BFF层"]
categories: ["BFF"]

contentCopyright: MIT
mathjax: true
autoCollapseToc: true
---
这个系列是基于在鹅厂的工程实践，抽象出来的MVP版本实践。
本文就是为了BFF层设计的前端基建内容，在做前端基建之前，还是要再次复习一下我们之前的[BFF服务端架构设计](/post/bff的服务端设计)，方便我们更好的配合它做基建。

这套工程化是根据当前的BFF需求（下图所示）而设计的。
![nova-core](/images/nova-bff/BFF-structure.png)
这套架构提供统一的入口，通过多页面入口来分发不同的系统（应用）。

**本文内容较长，核心内容使用👍🏻（👍）的标志标注，补充说明某个概念使用双分割线包裹。**

## 这一节要干啥
设计BFF是想解耦纯后端和页面访问，BFF层做一部分请求的工作，更好的服务页面的接口需求。
而上一章节的服务端设计，是通过封装koa，实现了一套egg.js的架构。用一系列的中间件、loader去实现bff层的底座。
![nova-core](/images/nova-bff/nova-core-structure.png)

仔细看bff层的业务逻辑中的核心有一个页面模版，也就是我们koa-core要去访问、解析tpl文件，展示层在通过koa-router的路由访问对应的页面。

而这里的模版就是我们本节要去实现的，它必然是动态生成的。要把/app/pages下的对应页面解析成对应的页面模版。
![nova-core](/images/nova-bff/1742982008281.jpg)

但是实际开发中我们会有很多资源依赖，可能会用react或者vue开发，可能会用less\sass。
所以要用打包工具去处理。

这一节会做两件事：
1. 前端工程化
2. 为了让开发过程更加高效，做一部分前端基础建设。

综上所述，这一节要完成下图中间部分：
![webpack](/images/nova-bff/webpack.png)
当做完解析后，输出的产物，koa服务端就可以直接访问了。

## 前端工程化
前端工程化主要打包工具来实现，至于你用vite还是webpack，还是xxx，都不重要，重要的是从工程化的思路去处理，不同环境下该做什么，每种情况处理的逻辑基本都是相通的。

我选了webpack5来实践。
在回顾一下这张图：![webpack](/images/nova-bff/webpack.png)
解析引擎要做三件事：
1. 解析编译
2. 模块分包
3. 压缩优化
不同的打包工具，api使用上不同，但是核心逻辑都是这些，继续细化一下。
### 解析编译
- 通过入口(entry)，进行依赖分析，遇到import和其他引用的资源，都认为是module
- 然后module按照不同的rules通过合适的loader进行处理
- 最终生成output产物。

***
👍 loader怎么寻找的
```javascript
module: {
    rules: [
      //? 例如webpack怎么找到vue-loader
      {
        test: /\.vue$/,
        use: {
          loader: 'vue-loader'
        }
      },
    ]
}
```


在 webpack 的模块解析机制中，loader 的查找遵循规则：**从当前目录向上找**。

举个🌰：
  `当执行 node ./app/webpack/dev.js 时`，node_modules 查找顺序：
  1. /Users/wushao/wushaoDev/FE-stuty/nova/app/webpack/node_modules ❌
  2. /Users/wushao/wushaoDev/FE-stuty/nova/app/node_modules ❌
  3. /Users/wushao/wushaoDev/FE-stuty/nova/node_modules ✅ (正确位置)


**路径解析伪代码逻辑**：
```javascript
// 伪代码演示 webpack 内部查找过程
function resolveLoader(loaderName) {
  // 1. 检查是否绝对路径
  if (path.isAbsolute(loaderName)) return loaderName
  
  // 2. 相对路径解析（从当前文件所在目录）
  if (loaderName.startsWith('./')) {
    return path.join(__dirname, loaderName)
  }
  
  // 3. 从 node_modules 向上递归查找（当前项目的 node_modules）
  return require.resolve(loaderName) 
}
```

如果要自定义 loader 解析路径，可以修改配置（但不推荐）：
```javascript
// 在 module.exports 中添加：
resolveLoader: {
  modules: [
    'node_modules', // 默认值
    '/global/node_modules' // 自定义全局路径（不推荐）
  ]
}
```
***
解析编译的前两步的一些基础操作，开发环境和生成环境都需要，可以使用base.js来抽象，至于产物，生产和开发环境差别很大，要单独处理。

在最终的构建阶段会通过配置插件，在打包的不同生命周期中生效，去改变打包的结果，例如要生成html或者tpl

```javascript

  plugins: [
    // 把vue中的script、style标签应用 modules.rules的对应规则
    new VueLoaderPlugin(),
    // 把第三方库暴露到window context下
    new webpack.ProvidePlugin({
      Vue: 'vue',
      axios: 'axios',
      '_': 'lodash',
    }),
    //! 定义全局常量，例如vue相关的
    new webpack.DefinePlugin({
      __VUE_OPTIONS_API__: 'true', // 支持options api
      __VUE_PROD_DEVTOOLS__: 'false', // 禁用调试工具，打包时不需要这个了
      __VUE_PROD_HYDRATION_MISMATCH_DETAILS__: 'false', // 禁用生产环境显示水合信息
    }),
    // 构造最终的页面模版
    new HtmlWebpackPlugin({
      filename: '', // 把文件生成到哪
      template: path.resolve(process.cwd(), "./app/view/entry.tpl"), // 使用的原始模版
      chunks: [entryName],
    })
  ],
```
***
可以看到插件中：`__VUE_PROD_HYDRATION_MISMATCH_DETAILS__: 'false', // 禁用生产环境显示水合信息`
在 Vue 和 React 这类前端框架里，“水合”（Hydration）是个关键概念，“水合信息”就和水合过程产生的数据或者状态有关。

**水合的概念**
在服务器端渲染（SSR）或者静态站点生成（SSG）的场景中，服务端先把 HTML 渲染好，然后发送到客户端。客户端拿到这些 HTML 后，要把它变成可交互的应用程序，这个过程就是水合。

简单来说，水合就是把静态的 HTML 和框架里的 JavaScript 代码关联起来，让页面具有交互性。

**水合信息的本质**：
水合信息指的是在水合过程中用到的、和组件状态、事件监听器等相关的数据。具体包含以下内容：
- **组件状态**：像组件里的变量、数据这些状态信息。在水合的时候，客户端要把这些状态恢复到和服务端渲染时一样的状态。
- **事件监听器**：比如 `click`、`input` 这类事件的监听器。水合过程会把这些事件监听器添加到对应的 DOM 元素上，这样页面才能响应用户的操作。
- **生命周期钩子**：组件的生命周期钩子函数在水合的时候会被触发，从而保证组件能正确地初始化和渲染。

下面是 Vue 和 React 中关于水合的简单示例代码：

Vue 示例
```vue
<template>
  <div>
    <button @click="increment">点击: {{ count }}</button>
  </div>
</template>

<script>
export default {
  data() {
    return {
      count: 0
    };
  },
  methods: {
    increment() {
      this.count++;
    }
  }
};
</script>
```
在 Vue 的 SSR 中，服务端会渲染出初始的 HTML，包含 `count` 的初始值 `0`。客户端进行水合时，会恢复 `count` 的状态，并且给按钮添加 `click` 事件监听器，这样点击按钮就能更新 `count` 的值。

React 示例
```jsx
import React, { useState } from 'react';

const Counter = () => {
  const [count, setCount] = useState(0);

  return (
    <div>
      <button onClick={() => setCount(count + 1)}>点击: {count}</button>
    </div>
  );
};

export default Counter;
```
在 React 的 SSR 里，服务端会渲染出初始的 HTML，客户端水合时会恢复 `count` 的状态，同时给按钮添加 `onClick` 事件监听器，让按钮可以正常响应点击事件。

**禁用生产环境显示水合信息的原因**

在生产环境中禁用水合信息的显示，主要是为了提高性能和安全性。显示水合信息可能会带来额外的开销，而且有可能泄露一些敏感的应用程序状态信息。通常框架会默认在生产环境下关闭这些调试信息的显示。 
***
上面构造最终的页面模版，因为涉及到多页面，不希望写多份入口文件和多个渲染模版：
```javascript
// 多入口
entry: {
  'entry.page1': './app/pages/page1/entry.page1.js',
  'entry.page2': './app/pages/page2/entry.page2.js',
}
// 多个渲染模版
[
  new HtmlWebpackPlugin({
    filename: '', // 把文件生成到哪
    template: path.resolve(process.cwd(), "./app/view/entry.tpl"), // 使用的原始模版
    chunks: [entryName],
  }),
  new HtmlWebpackPlugin({
    filename: '', // 把文件生成到哪
    template: path.resolve(process.cwd(), "./app/view/entry.tpl"), // 使用的原始模版
    chunks: [entryName],
  }),
  // ...
]
 
```
所以在base.js初始化时，动态构造多页面入口和多页面渲染模版：
```javascript
const glob = require("glob");

const entryList = {}
const htmlWebpackPluginList = []

const pageList = path.resolve(process.cwd(), './app/pages/**/entry.*.js')
//!!! 借助glob获取所有的filePath
glob.sync(pageList).forEach(filePath => {
  //这个filePath就是 相当于'xxx/app/pages/page1/entry.page1.js'
  
  //去掉.js后缀，拿到前面的名字，例如entry.page1
  const entryName = path.basename(filePath, '.js')
  
  //!!! 构造多入口的对象
  entryList[entryName] = filePath
  // 相当于写死的这个配置
  // {
  //   'entry.page1': './app/pages/page1/entry.page1.js',
  //   'entry.page2': './app/pages/page2/entry.page2.js',
  // }
  htmlWebpackPluginList.push(
    //! 添加的是HtmlWebpackPlugin对象
    new HtmlWebpackPlugin({
      filename: path.resolve(
        process.cwd(),
        "./app/public/dist/",
        `${entryName}.tpl`
      ),
      template: path.resolve(process.cwd(), "./app/view/entry.tpl"),
      chunks: [entryName],
    })
  );
  
});
```
### 👍模块分包
如果多个组件使用一个公共文件，或者都引用了vue，没有必要都打到一个entry文件中。

合理的分包，根据不同包的使用频率、改动频率，更好的利用浏览器的并发请求特性，也能更好的利用缓存。
例如vue库、某些ui库改的机会不多，单独打包出来。

***
更重要的是，webpack的运行时代码，如果不单独处理，打到entry文件中，当某个chunk内容改变，运行时代码不变，但hash值也会改变，影响缓存。

分离后,只有运行时代码改变才会影响运行时chunk的hash
webpack运行时代码包含：
- webpack的模块加载系统
- 模块缓存逻辑
- 异步chunk加载逻辑
***

配置分包策略，一般分为三种包：
1. vendor包，代表第三方包，基本不会改动，除非依赖版本升级
2. common，代表一些业务组件的公共部分，单独提取出来，改动较少
3. entry.page1_3c02631e.bundle 包，代表不同的页面（业务）组件代码，经常改动

这样处理后，可以实现：
- 更好的缓存效果 
- 减少主包体积 
- 运行时代码从主包中抽离， runtime很少改变,可以长期缓存，runtime可以和其他chunk并行加载

```javascript
  optimization: {
    splitChunks: {
      chunks: 'all', // all 异步 同步都分割。例如动态导入（import()）的代码只会在需要时候才加载，减少初始加载时间
      // minSize: 20000, //生成 chunk 的最小体积（以 bytes 为单位）。
      maxAsyncRequests: 10, //按需加载时（异步加载）的最大并行请求数
      maxInitialRequests: 10, //入口点的最大并行请求数。
      //! 具体的三个分包，缓存组
      cacheGroups: {
        vendor: {
          //! 匹配node_modules目录，windows和Linux斜杠
          test: /[\\/]node_modules[\\/]/,
          name: 'vendor', //模块名称
          priority: 20,
          enforce: true, //强制执行
          reuseExistingChunk: true, //重用之前页面已打出来的包
        },
        common: {
          name: 'common',
          minChunks: 2, // 被几处引用过，这里配置被两处引用就认为是公共模块
          minSize: 1, //最小分割文件大小 byte
          priority: 10,
          reuseExistingChunk: true, //重用之前页面已打出来的包
        }
      }
    },
    // 将webpack运行时代码打包到runtime.js
    runtimeChunk: true
  }
```

### 👍🏻👍🏻👍🏻生产环境的优化
1. 具体的output
```javascript
output: {
    filename: "js/[name]_[chunkhash:8].bundle.js",
    // 自定义的文件路径
    path: path.join(process.cwd(), "./app/public/dist/prod"),
    //! 根路径, 注意要用绝对路径! /开头
    publicPath: "/dist/prod",
    //! 配置跨域
    crossOriginLoading: "anonymous",
  },
```
***
chunkhash和contenthash区别
1. **生成规则**:
- chunkhash基于 Chunk 内容生成，根据每个 chunk（代码块）的内容来生成哈希值。在 Webpack 打包过程中，代码会被分割成多个 chunk，chunkhash 会为每个 chunk 计算一个唯一的哈希值。

相同 Chunk 内容相同哈希：只要 chunk 的内容不变，生成的 chunkhash 就不会改变。例如，某个 JavaScript 文件属于一个特定的 chunk，当该文件内容没有发生变化时，其对应的 chunkhash 也不会改变。
- contenthash基于文件内容生成：contenthash 是根据每个文件的具体内容来生成哈希值。它会逐字节地比较文件内容，只要文件内容有任何改变，生成的 contenthash 就会不同。

文件独立性：每个文件都有自己独立的 contenthash，不受其他文件的影响。即使两个文件属于同一个 chunk，只要它们的内容不同，contenthash 也会不同。

2. **使用场景**
- chunkhash适用于代码分割场景：在大型项目中，通常会使用代码分割（如动态导入）将代码分割成多个 chunk，以实现按需加载。使用 chunkhash 可以确保当某个 chunk 的内容发生变化时，只有该 chunk 的文件名会改变，而其他 chunk 的文件名保持不变，从而避免不必要的缓存失效。

示例：假设一个项目有一个主 chunk 和多个动态导入的 chunk，当动态导入的 chunk 内容发生变化时，只有该 chunk 的文件名会更新，主 chunk 的文件名不变，用户在访问页面时，主 chunk 可以继续使用浏览器缓存，减少了不必要的网络请求。
- contenthash适用于 CSS 文件，使用 contenthash 可以确保当 CSS 文件内容发生变化时，其文件名也会改变，从而让浏览器重新下载更新后的 CSS 文件。由于 CSS 文件通常是独立于 JavaScript 文件进行处理的，使用 contenthash 可以更精确地控制 CSS 文件的缓存。

```javascript
plugins: [
    new MiniCssExtractPlugin({
        filename: '[name].[contenthash].css',
        chunkFilename: '[id].[contenthash].css'
    })
]
```
除了 CSS 文件，对于其他静态资源（如图片、字体等），也可以使用 contenthash 来确保资源内容更新时，文件名也会相应改变，从而使浏览器能够获取到最新的资源。
***

2. 多线程build，使用terserPlugin
```javascript
const TerserPlugin = require('terser-webpack-plugin')
const os = require('os')
// 取代happypack，用线程池来并行处理module，加快打包（构建）速度
// 只在处理耗时的 loader 前置添加这个loader:
// 例如适合处理计算密集型的加载器，像 babel-loader、less-loader 等。
// 对于一些轻量级的加载器，使用 thread-loader 可能不会带来明显的性能提升，
// 甚至可能由于进程间通信的开销而导致性能下降。
//! 必须放在加载器链的第一个位置，这样后续的加载器才能在独立的进程中执行。
//!!! 一个例外：MiniCssExtractPlugin.loader 要在它前面
// 因为：thread-loader会把后续的 loader 放到独立的 worker 进程里执行，
// 以此提升构建速度。
// 但 MiniCssExtractPlugin.loader 要在主进程里和 Webpack 构建流程紧密配合
// 所以不能放在 thread-loader 后面。
const threadLoader = require('thread-loader');
//! 预热工作线程池（worker）:在启动时预先加载一些模块, 会增加初始启动时间
// 不过会减少后续的加载时间，所以要依据项目的规模和构建频率来决定是否启用。
threadLoader.warmup(
  {
    //!!! 配置池选项，这些选项必须与后续在 loader 中使用的选项一样
    // 也就是说后面module.rules中的thread-loader的option必须和下面的一样，才能正确预热。
    //! 设置worker数量，根据需求调整，默认cpu - 1
    workers: os.cpus().length - 1, 
    workerParallelJobs: 50, // 每个工作线程的并行任务数
    //! 额外的 Node.js 参数
    workerNodeArgs: ['--max-old-space-size=2048'],
    poolRespawn: false, // 是否允许重新生成死亡的工作线程池
    poolTimeout: 2000, // 工作线程池空闲时的超时时间
    poolParallelJobs: 50, // 工作线程池分配给每个工作线程的任务数
    name:'nova-pool', // 工作线程池的名称
  },
  [
    // 列出你想要预先加载到工作线程池中的模块
    'babel-loader',
  ],
);
```
3. 资源优化：
- 图片压缩、合适的小图用url编码，默认base64
- 字体处理，按需加载字体库，或者使用cdn字体库
4. 构建（打包）流程优化
- 持久化本地缓存
- 并行处理耗时的那些loader，例如在babel-loader、css-loader等loader链头部使用thread-loader
- 去除无用代码：js代码用TreeShaking、PureCSS去除没有用到的css
5. 打包输出的优化
- 清理之前的目录内容
```javascript
new CleanWebpackPlugin(["public/dist"], {
  root: path.resolve(process.cwd(), "./app/"),
  exclude: [], //排除xxx
  verbose: true, //去除日志
  dry: false,
}),
```
- 提取css文件，可以更好的利用浏览器并行请求的特性。
```javascript
// webpack.config.js
const MiniCssExtractPlugin = require('mini-css-extract-plugin');

module.exports = {
    module: {
        rules: [
            {
                test: /\.css$/,
                use: [
                    MiniCssExtractPlugin.loader,
                    'css-loader'
                ]
            }
        ]
    },
    plugins: [
        new MiniCssExtractPlugin({
            filename: '[name].[contenthash].css',
            chunkFilename: '[id].[contenthash].css'
        })
    ]
};
```
- 预加载和预取
[内置模块](https://webpack.docschina.org/guides/code-splitting/#prefetchingpreloading-modules)
6. 安全性的插件
```javascript
// 允许你在 Webpack 构建过程中，自动向 HTML 文件里的特定标签（如 <script>、<link> 等）添加自定义属性。
// 在你需要为这些标签添加额外的属性以满足特定需求时非常有用，
// 比如添加 defer、async 属性来控制脚本的加载行为，或者添加自定义的 data-* 属性用于前端脚本进行数据传递和交互。
const HtmlWebpackInjectAttributesPlugin = require("html-webpack-inject-attributes-plugin");

// 浏览器请求资源时，不发送用户的身份凭证
  new HtmlWebpackInjectAttributesPlugin({
    crossorigin: 'anonymous'
  })
```
***
crossorigin 是 HTML 标签（主要是 `<script>、<link>、<img>`等）的一个属性,
用于控制跨域资源的请求方式，它有以下两个主要取值：

1. anonymous：**表示在请求跨域资源时，不会发送用户的凭证（如 cookie、HTTP 认证信息等）。
浏览器会发起一个跨域请求，但不会包含任何用户的身份信息。**
2. use-credentials：表示在请求跨域资源时，会发送用户的凭证。
如果服务器端没有正确配置 CORS（跨域资源共享）允许携带凭证，请求将会失败。
***
之前的分包策略，万一有的包太大，请求很慢呢？

**借助performance发现**
```javascript
performance: {
  hints: false,
  maxAssetSize: 250000, // 限制单个资源文件最大250k
  maxEntrypointSize: 400000, // 入口点所有资源文件大小
},
```
超了之后可以用警告或者错误提示，这一点提醒我们：在打包时要关注分包大小。
***
### 减小 Webpack 打包体积

#### 1. 代码分割（Code Splitting）
代码分割能把大的代码包拆分成多个小的代码包，按需加载，从而减少初始加载的资源大小。Webpack 支持多种代码分割方式，如入口点分割、动态导入等。

**动态导入示例**：
```javascript
// 在需要使用模块的地方动态导入
async function loadComponent() {
  const { default: component } = await import('./path/to/component');
  return component;
}
```

#### 2. 压缩代码
使用插件对 JavaScript、CSS 等代码进行压缩，去除多余的空格、注释和不必要的代码。
```javascript
optimization: {
    minimize: true,
    minimizer: [
      //! 多线程压缩和混淆js，并移除console.
      new TerserPlugin({
        parallel: true, // 启用多核CPU加速
        terserOptions: {
          compress: {
            drop_console: true, // 去除console
          },
        },
      }),
      // 压缩css
      new CssMinimizerPlugin(),
    ],
  },
```
#### 3. 去除无用代码（Tree Shaking）
Tree Shaking 是一种消除未使用代码的技术。Webpack 在生产模式下默认支持 Tree Shaking，但需要确保代码使用 ES6 模块语法，并且使用支持 Tree Shaking 的打包工具和配置。

```javascript
// utils.js
export function add(a, b) {
  return a + b;
}

export function subtract(a, b) {
  return a - b;
}

// main.js
import { add } from './utils';
const result = add(1, 2);
```
在上述代码中，`subtract` 函数未被使用，在生产构建时会被 Tree Shaking 移除。

#### 4. 图片优化
使用 `image-webpack-loader` 等插件对图片进行压缩和优化，减少图片文件的大小。
上面只是在处理模块阶段基本的优化，构建的阶段，要进行更细致的压缩image-minimizer-webpack-plugin。

```javascript
npm install image-minimizer-webpack-plugin imagemin imagemin-gifsicle imagemin-mozjpeg imagemin-pngquant imagemin-svgo --save-dev
const ImageMinimizerPlugin = require('image-minimizer-webpack-plugin');

module.exports = {
  module: {
    rules: [
      {
        test: /\.(png|jpg|gif)$/i,
        use: [
          {
            loader: 'file-loader'
          },
          {
            loader: ImageMinimizerPlugin.loader,
            options: {
              minimizer: {
                implementation: ImageMinimizerPlugin.imageminMinify,
                options: {
                  plugins: [
                    ['gifsicle', { interlaced: true }],
                    ['jpegtran', { progressive: true }],
                    ['optipng', { optimizationLevel: 5 }]
                  ]
                }
              }
            }
          }
        ]
      }
    ]
  }
};
```

#### 5. 使用 CDN
对于一些常用的第三方库，如 React、Vue、jQuery 等，可以使用 CDN（内容分发网络）来加载，减少本地打包的资源大小。

```html
<!-- 在 HTML 文件中使用 CDN 加载 React -->
<script src="https://cdn.jsdelivr.net/npm/react@17.0.2/umd/react.production.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/react-dom@17.0.2/umd/react-dom.production.min.js"></script>
```

#### 6. 配置 externals
如果使用了 CDN 加载某些库，可以通过 `externals` 配置告诉 Webpack 这些库不需要打包到最终的代码中。

```javascript
module.exports = {
  externals: {
    react: 'React',
    'react-dom': 'ReactDOM'
  }
};
```

通过以上这些方法，可以有效地减小 Webpack 打包后资源的大小，提高应用的加载性能。 

## 👍🏻👍🏻👍🏻通用优化思路
分析上面的一系列操作，可以总结出一些规律：无论什么打包工具，在做大型项目时，都有三类优化需要去做，根据对应打包工具的文档和社区做就行。

重要是：
1. 要知道做什么能优化。
2. 什么情形下该优化。
3. 如何衡量优化后的效果。

这一节来解决这三个问题。

从性能优化、构建优化和代码质量优化三个方式来做优化。
### 1、性能优化（直接影响用户体验）
```javascript
// webpack.prod.js
optimization: {
  splitChunks: { // 代码分割
    cacheGroups: {
      vendor: { // 第三方包分离
        test: /[\\/]node_modules[\\/]/,
        name: 'vendor'
      },
      common: { // 公共模块分离
        minChunks: 2
      }
    }
  },
  runtimeChunk: true // 运行时代码分离
},
plugins: [
  new MiniCssExtractPlugin(), // CSS 提取
  new PurgeCSSPlugin(), // 删除无用 CSS
  new CssMinimizerPlugin(), // CSS 压缩
  new TerserPlugin() // JS 压缩
]
```
目的是：
- 减少首屏资源体积（代码分割）
- 提升缓存利用率（合适的分包策略）
- 减少 CSS/JS 文件体积（压缩优化）

### 2、构建优化（开发体验优化）
```javascript
// webpack.prod.js
{
  loader: "thread-loader", // 线程池加速
  options: {
    workers: os.cpus().length - 1
  }
}
```
目的是：
- 多进程并行构建（thread-loader）
- 预热线程池（warmup 配置）
- 开发环境热更新（HMR）

### 3、代码质量优化
```javascript
// webpack.base.js
{
  test: /\.js$/,
  include: [path.resolve('./app/pages')], // 限定 Babel 编译范围
  use: ['babel-loader']
}
```
**[预加载和预取](https://webpack.docschina.org/guides/code-splitting/#prefetchingpreloading-modules)**：
```javascript
// webpack.prod.js
plugins: [
  new PreloadWebpackPlugin({
    rel: 'preload',
    include: 'initial'
  })
]
```
目的是：
- 避免全量编译（精准 include 配置）
- 类型检查（通过 TS/Vue 模板编译）
- 各种lint校验
- 合适时机加载相关资源

| 优化类型        | 具体方案                          | 适用场景               |
|----------------|----------------------------------|----------------------|
| 加载性能优化    | 代码分割 (SplitChunksPlugin)     | 多路由/多入口应用     | 
| 缓存优化        | 文件名哈希 (contenthash)         | 长期缓存策略          |
| 资源压缩        | 图片压缩 (image-webpack-loader)  | 图片资源较多的项目    |
| 构建速度优化    | 多进程构建 (thread-loader)       | 大型项目构建加速      |

3. **Bundle 分析**：
```bash
npx webpack-bundle-analyzer stats.json
```
### 👍🏻衡量优化效果

1. **构建速度对比** (使用 `speed-measure-webpack-plugin`)
```bash
npm install --save-dev speed-measure-webpack-plugin
```

```javascript
const SpeedMeasurePlugin = require('speed-measure-webpack-plugin')
const smp = new SpeedMeasurePlugin()

module.exports = smp.wrap(webpackConfig) // 包裹原配置
```

**输出示例**：
```
LoaderA: 12.34s
LoaderB: 8.12s 
Total build time: 38.56s (优化前 62.34s)
```

2. **体积分析** (使用 `webpack-bundle-analyzer`)
```bash
npm install --save-dev webpack-bundle-analyzer
```

```javascript
const { BundleAnalyzerPlugin } = require('webpack-bundle-analyzer')

// 在 plugins 数组中添加：
new BundleAnalyzerPlugin({
  analyzerMode: 'static',
  reportFilename: 'bundle-report.html'
})
```

**输出效果**：
```
vendor.xxxx.js    1.2MB → 876KB (↓27%)
entry.page1.js    512KB → 324KB (↓36%)
```
***

还有一种生成静态文件的分析方法：在 Webpack 工程中生成`stats.json`

```bash
# 在项目根目录执行（MacOS）
webpack --profile --json > stats.json
```

或通过配置生成（推荐）：
```javascript
// 修改 webpack 配置
webpack(webpackConfig, (err, stats) => {
  if (err) throw err
  
  // 生成 stats.json
  fs.writeFileSync(
    path.resolve(__dirname, 'stats.json'),
    JSON.stringify(stats.toJson('verbose'))
  )
})
```

#### stats.json 包含的关键信息
| 分析维度          | 具体数据                                                                 | 优化方向案例                                                                 |
|------------------|------------------------------------------------------------------------|--------------------------------------------------------------------------|
| **模块体积**      | 每个模块的原始大小、gzip后大小                                            | 发现 2.8MB 的 `moment.js` → 改用 `dayjs`                                 |
| **重复依赖**      | 相同模块在不同 chunk 中的重复次数                                         | `lodash` 在 5 个 chunk 重复 → 提取到公共 chunk                           |
| **入口依赖**      | 首屏加载必须的核心资源列表                                                | `main.js` 含 30+ 路由组件 → 改为动态导入                                 |
| **第三方占比**    | `node_modules` 代码在总包中的比例                                         | 占比 78% → 使用 CDN 加载 `react`、`vue` 等                                |
| **缓存失效**      | 文件哈希值变化频率                                                        | `vendor.js` 每周都变 → 调整 splitChunks 策略                             |

#### 典型分析案例
结合自己的项目去分析，以我的代码片段为例：
```javascript
// stats.json 片段示例
{
  "assets": [
    {
      "name": "vendor.1234.js",
      "size": 1024000,  // 1MB
      "chunks": ["vendors~main"], 
      "chunkNames": ["vendors~main"]
    },
    {
      "name": "src_pages_Home.5678.js",
      "size": 256000,   // 256KB
      "chunks": ["src_pages_Home"]
    }
  ]
}
```

对应的优化建议：
```javascript
// 修改分包策略
optimization: {
  splitChunks: {
    cacheGroups: {
      vendor: {
        test: /[\\/]node_modules[\\/](react|react-dom)[\\/]/,
        name: 'react-vendor' // 单独提取 React 相关
      }
    }
  }
}
```

也可视化分析：
```bash
npx webpack-bundle-analyzer /xxx/stats.json
```

浏览器查看：
```
http://127.0.0.1:8888
```

***

3. **真实场景测试** (Chrome DevTools)
```javascript
// 在项目入口添加性能监控
console.time('First Paint')
window.addEventListener('load', () => {
  console.timeEnd('First Paint') // 优化前 3.2s → 优化后 1.8s
})
```
***
应该输出一份这个类似的报告作为结果：
| 优化类型         | 典型提升幅度       | 数据来源                  |
|----------------|------------------|-------------------------|
| 代码分割         | 首屏体积↓30-50%  | Webpack 官方性能报告       |
| 多线程构建       | 构建时间↓20-40%  | Terser 官方基准测试        |
| 图片转 WebP     | 图片体积↓25-35%  | Google 开发者文档         |
| 按需引入 (lodash)| 包体积↓40-60%    | Lodash 官方迁移指南        |

结论：

在系统优化中，通过代码分割和缓存策略，首屏资源体积减少了约40%，构建时间从平均90秒缩短到55秒左右。具体来说：
1. 将 `lodash` 改为按需引入，减少 420KB 的包体积
2. 使用 `thread-loader` 后，`babel-loader` 阶段的耗时减少 35%"

通过 `webpack-bundle-analyzer` 分析发现，`node_modules` 代码占比达78%。实施分包策略后：
- 首屏资源从 2.1MB 降至 1.4MB (↓33%)
- 二次加载因缓存命中率提升，加载时间从 3.2s 降至 1.1s
- 完整构建耗时从 86s 优化至 49s (↓43%)"
***
## 👍 开发环境优化
对比[生产环境的优化](#生产环境的优化)，基本上除了webpack.base.js，额外做的优化不多，为了开发调试方便，会启用sourcemap
```javascript
devtool: 'eval-cheap-module-source-map',
```
***
👍🏻sourcemap分类：
对于开发环境
以下选项非常适合开发环境，通常会从以下四种挑一个：
![devtools](/images/nova-bff/devtools.jpg)

开始时期望看到源码，所以通过生成代码后的信息，选择后两种，再从build的速度，最终选择了`eval-cheap-module-source-map`
> 1. eval - 每个模块都使用 eval() 执行，并且都有 //# sourceURL。此选项会非常快地构建。主要缺点是，由于会映射到转换后的代码，而不是映射到原始代码（没有从 loader 中获取 source map），所以不能正确的显示行数。
> 2. eval-source-map - 每个模块使用 eval() 执行，并且 source map 转换为 DataUrl 后添加到 eval() 中。初始化 source map 时比较慢，但是会在重新构建时提供比较快的速度，并且生成实际的文件。行数能够正确映射，因为会映射到原始代码中。它会生成用于开发环境的最佳品质的 source map。
> 3. eval-cheap-source-map - 类似 eval-source-map，每个模块使用 eval() 执行。这是 "cheap(低开销)" 的 source map，因为它没有生成列映射(column mapping)，只是映射行数。它会忽略源自 loader 的 source map，并且仅显示转译后的代码，就像 eval devtool。
> 4. eval-cheap-module-source-map - 类似 eval-cheap-source-map，并且，在这种情况下，源自 loader 的 source map 会得到更好的处理结果。然而，loader source map 会被简化为每行一个映射(mapping)。

[官网详细分类解释](https://webpack.docschina.org/configuration/devtool/#devtool)

[官网分类示例代码](https://github.com/webpack/webpack/tree/main/examples/source-map)
***

开发时的动态代码不落盘，直接放到内存中，通过HMR做热更新。
主要是理解HMR原理。

### 👍👍👍热更新原理
要做热更新，先知道要做哪些事情，才能做到：本地代码变了，页面跟着刷新。
是不是需要一个服务能处理静态文件目录（static），能监听源码变化，同时他还能和页面进行通信，得让页面有可以双向通信的能力，将变化后的代码注入到页面中。
这个服务，就是所谓的devServer，他有三个能力：
1. 监控源码变化
2. 往浏览器注入一些代码，使浏览器具备双向通信的能力，本地代码变化了告诉浏览器，浏览器去拉新代码，刷新页面
3. 开辟适量的内存空间，存储代码片段。
所以原理如图所示：
![HMR](/images/nova-bff/HMR.png)

压缩优化完的代码走两个分支：
1. 分支2：tpl模版直接落盘就好
2. 分支1：模版依赖的资源，通过访问一个在线地址动态更新，而这个动态地址就指向内存中的代码片段。这个分支把每次优化后的代码注入到devServer的内存中即可。

实现上，用express做devServer，在用两个express能够使用的中间件：`webpack-dev-middle、webpack-hot-middleware`，实现监控能力、双向通信的能力。
![HMR-implement](/images/nova-bff/HMR-implement.png)
其中：
- `webpack-dev-middle`中间件使express服务器具备监控能力、将 webpack 编译输出托管到内存文件系统（分支1）、落地tpl文件（分支2）

```javascript
// DevMiddleware 内部实现伪代码
compiler.outputFileSystem = new MemoryFileSystem()
compiler.watch({}, (err, stats) => {
  // 将编译结果存入内存
})
```

- `webpack-hot-middleware` 实现`HMR`热模块替换

用代码描述的话：
1. 在dev.js中要暴露devServer的配置（尤其注意官方要求的`HMR_PATH: '__webpack_hmr'`）
2. 重写入口文件，除第三方包外需要做hmr 增加热更新的配置地址。
```javascript
// webpack.dev.js核心代码
// devServer配置
const DEV_SERVER_CONFIG = {
  HOST: '127.0.0.1',
  PORT: 9002,
  HMR_PATH: '__webpack_hmr', // 官方规定
  TIMEOUT: 20 * 1000, // 20秒
}

// 开发环境希望的是entry入口文件改了，就更新，所以肯定不是固定的入口路径
// 要通过热替换模块（HMR）来实现代码更改，通知页面更新
Object.keys(webpackBaseConfig.entry).forEach(entryName => {
  //! 回忆一下三种分包策略，第三方包肯定不需要做hmr
  if(entryName !== 'vendor') {
    const {
      HOST,
      PORT,
      HMR_PATH,
      TIMEOUT,
    } = DEV_SERVER_CONFIG
    //! 重新给入口文件赋值
    webpackBaseConfig.entry[entryName] = [
      // 原来的主入口文件
      webpackBaseConfig.entry[entryName],
      // hmr官方入口，client后面的查询字符串部分是用来给客户端传递配置参数的
      `webpack-hot-middleware/client?path=http://${HOST}:${PORT}/${HMR_PATH}&timeout=${TIMEOUT}&reload=true`
    ]
  }
})

const {
  HOST,
  PORT,
} = DEV_SERVER_CONFIG
// 开发环境webpack配置
const webpackConfig = merge.smart(webpackBaseConfig, {
  mode: "development",
  // 开启sourcemap，通过代码映射关系，方便开发环境调试代码
  devtool: 'eval-cheap-module-source-map',
  // 开发阶段的输出产物
  output: {
    filename: "js/[name]_[chunkhash:8].bundle.js",
    // 文件放哪
    path: path.resolve(process.cwd(), "./app/public/dist/dev/"),
    //! 根路径, 想想开发环境这里应该填什么
    // 应该用上面的devServer配置，组装成有效的publicPath
    // 也就是说会把输出的产物放到上面devServer配置后的路径上
    // 既然开发环境想用热更新，他就要是个可用的本地链接。
    publicPath: `http://${HOST}:${PORT}/public/dist/dev/`,
    globalObject: 'this',
  },
  // 开发阶段的插件，最重要的就是热更新插件
  plugins: [
    //! 开发阶段有了这个插件，才能让应用程序代码更新了，立马反应到页面变化上
    new webpack.HotModuleReplacementPlugin({
      // 默认值为 false。
      // 当设置为 true 时，模块热替换分两步：先更新所有的模块，再重新构建依赖图；
      // 而设置为 false 时，模块热替换会一次性完成所有操作。
      // 通常来说，false 能加快热替换的速度，不过可能会消耗更多的内存。
      multiStep: false,
    })
  ]
});

module.exports = {
  DEV_SERVER_CONFIG, //暴露给dev.js的开发服务器使用
  webpackConfig
}
```

上面output的publicPath就是内存中的地址，当访问tpl时，动态加载的依赖就是他的路径：
![](/images/nova-bff/page222.jpg)
如果你更新代码后，这个路径会变：
![](/images/nova-bff/page111.jpg)

devServer实现上，用express来启动即可。
```javascript
/ 通过webpack.dev.js获取devServer配置和webpack开发环境配置
const {
  DEV_SERVER_CONFIG,
  webpackConfig //开发配置
} = require('./config/webpack.dev')
const {
  PORT,
  HMR_PATH,
} = DEV_SERVER_CONFIG
const app = express()
//! 获取开发环境下，webpack解析后的内容
const compiler = webpack(webpackConfig)

// 指定静态文件目录,注意后面结尾的斜杠
app.use(express.static(path.join(__dirname, '../public/dist/')))

// 使用devMiddleware中间件，监听原始文件的变化
app.use(devMiddleware(compiler, {
  // 落到硬盘中的文件, 模板文件直接落盘就好
  writeToDisk: (filePath) => filePath.endsWith('.tpl'),
  // 资源路径
  publicPath: webpackConfig.output.publicPath,
  // 跨域配置
  headers: {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, PATCH, OPTIONS',
    'Access-Control-Allow-Headers': 'X-Requested-With, content-type, Authorization',
  },
  stats: {
    colors: true, //日志彩色
  }
}))
// 使用hotMiddleware中间件，实现热更新通信
app.use(hotMiddleware(compiler, {
  //! 热更新地址,记得前面加斜杠，跟路由的意思，最终会拼接成http://xxx:port/__webpack_hmr
  path: `/${HMR_PATH}`,
  log: () => {}
}))
```

**关键配置对应关系**
| 配置项                   | 作用域         | 影响范围                                                                 |
|-------------------------|---------------|--------------------------------------------------------------------------|
| `publicPath`            | DevMiddleware | 定义内存文件系统的访问路径 (http://localhost:9002/[publicPath]) |
| `path`                  | HotMiddleware | WebSocket 服务端监听路径 (ws://localhost:9002/[path])                    |
| `writeToDisk` 回调       | DevMiddleware | 控制哪些编译结果需要持久化到磁盘                                         |
| `headers` 跨域配置       | DevMiddleware | 解决开发时前后端分离导致的CORS问题            

启动后，会发现一个本地 服务器：
![hmr全流程](/images/nova-bff/hmr3.jpg)

更新代码时，代码更新，整个过程一直保持心跳：
![hmr全流程](/images/nova-bff/hmr1.jpg)
![hmr全流程](/images/nova-bff/hmr2.jpg)

至此，我们完成了手动实现热更新，也就是webpack开箱即用的devServer功能，完整的时序图：
![hmr全流程](/images/nova-bff/hmr-timeloop.png)

## 基础建设
统一收拢页面启动的入口代码：
![boot](/images/nova-bff/boot.jpg)
```javascript
import { createApp } from "vue";
import pinia from "$store";
import ElementPlus from "element-plus";
// import 'element-plus/dist/index.css'
import 'element-plus/theme-chalk/index.css'
import { createWebHashHistory, createRouter } from 'vue-router'
/**
 * 初始化页面入口
 * @param {import('vue').Component} pageComponent 页面组件实例
 * @param {Object} options 配置项 
 * @param {import('vue-router').RouterOptions} [options.routes] 路由配置
 * @param {Array<string>} [options.libs] 第三方库配置
 */
const initPage = (pageComponent, {routes = [], libs = []} = {}) => {
  const app = createApp(pageComponent)

  //! 在挂载渲染点之前，使用各种中间件
  app.use(pinia)
  app.use(ElementPlus)
  
  // 注册各种第三方组件，例如echarts
  if(libs && libs.length) {
    for(let i = 0; i < libs.length; i++) {
      app.use(libs[i])
    }
  }

  if(routes && routes.length) {
    const router = createRouter({
      history: createWebHashHistory(),
      routes,
    })
    app.use(router)
    // 等所有的路由（包括异步路由）加载好，再挂载
    router.isReady().then(() => {
      app.mount('#root')
    })
  } else {
    app.mount('#root')
  }
}

export default initPage
```
这样每个页面的entry.page.js只需要引入即可：
![boot](/images/nova-bff/page1.jpg)
### 请求适配器
通过适配器模式来封装请求模块，符合单一原则。

例如你现在用的axios请求库，后面想换成superagent，可以无缝衔接。
首先封装请求适配模块的基类：
```javascript
/**
 * 请求适配器基类
 */
export default class BaseRequestAdapter {
  //!!! 可以认为是两个抽象方法，子类必须实现它。
  /**
   * 发送请求
   * @param {Object} options 请求配置
   * @returns {Promise} 请求结果
   */
  request(options) {
    throw new Error('Adapter must implement request method');
  }

  /**
   * 处理响应
   * @param {Object} response 响应数据
   */
  handleResponse(response) {
    throw new Error('Adapter must implement handleResponse method');
  }
}

```
如果你用axios请求，你的实现类，必须实现上面的抽象方法：
```javascript
import BaseRequestAdapter from './base';

export default class AxiosAdapter extends BaseRequestAdapter {
  request(options) {
    return axios.request(options);
  }

  handleResponse(response) {
    return response.data;
  }
}

```
假如某一天你想换一个请求库superagent，实现上面的抽象方法即可：
```javascript
// 举例，如果不打算用axios了，换一个适配器即可
import BaseRequestAdapter from './base';
import superagent from 'superagent';

export default class SuperagentAdapter extends BaseRequestAdapter {
  request({ url, method, data, params, headers }) {
    return superagent[method](url)
      .query(params)
      .send(data)
      .set(headers);
  }

  handleResponse(response) {
    return response.body;
  }
}
```

再具体的请求实现那：
```javascript
import AxiosAdapter from './request-adapters/axios';

// 默认使用 axios 适配器
let requestAdapter = new AxiosAdapter();

/**
 * 设置请求适配器
 * @param {BaseRequestAdapter} adapter 请求适配器实例
 */
export const setRequestAdapter = (adapter) => {
  requestAdapter = adapter;
};
// 例如我们要切换到 superagent，只需要引入它，设置它即可
import { setRequestAdapter } from '$common/curl';
import SuperagentAdapter from '$common/request-adapters/superagent';

setRequestAdapter(new SuperagentAdapter());
```
而我们的真正请求只需要关心requestAdapter
```javascript
const curl = ({
  //...
}) => {
  // 组装参数
  const requestOptions = {
    //...
  }
  return requestAdapter.request(requestOptions)
    .then(response => {
    return Promise.resolve({
      //...
    })
  }).catch(err => {
    // ...
    return Promise.resolve(err)
  })
}

export default curl

// 页面请求时
import $curl from "$common/curl";

onMounted(async () => {
  const res = await $curl({
    url: "/api/project/list",
    method: "get",
    query: {
      page: 1,
      pageSize: 2,
    },
  });
  console.log("res is ", res);

});
```