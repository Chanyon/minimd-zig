### simple-markdown-parse
---
### 简单实现
- 标题语法
  ```
    # heading1 => <h1></h1>
    ## heading2 => <h2></h2>
    ### heading3 => <h3></h3>
    #### heading4 => <h4></h4>
    ##### heading5 => <h5></h5>
    ###### heading6 => <h6></h6>
  ```
- 段落语法
  ```
    hello world
    <p>hello world</p>
  ```
- 强调语法
  ```
    **test** => <strong>test</strong>
    *test* => <em>test</em>
    ***test*** => <strong><em>test</em></strong>
    __hello__ => <strong>test</strong>
  ```
- 引用语法
  ```
    > hello => <blockquote>hello</blockquote>

    > hello
    >
    >> world 
    => <blockquote>hello<blockquote>world</blockquote></blockquote> 
  ```
- 分隔线语法
  ```
    --- => <hr>
  ```
- 链接语法
  ```
    [link](https://github.com/) => <a href="https://github.com/">link</a>
    <https://github.com> => <a href="https://github.com/">https://github.com</a>
  ```
- 图片语法
  ```
    ![img](/assets/img/philly-magic-garden.jpg)
    => <img src="/assets/img/philly-magic-garden.jpg" alt="img">

    [![image](/assets/img/ship.jpg)](https://github.com/Chanyon)
    => <a href="https://github.com/Chanyon"><img src="/assets/img/ship.jpg" alt="image"></a>"
  ```
- 删除线
  ```
    ~~test~~ => <p><s>test</s></p>
    hello~~test~~world => <p>hello<s>test</s>world</p>
  ```
- code
  ```
  `test` => <code>test</code>
  `` `test` `` => <code> `test` </code>
  =```
    {
     "width": "100px",
     "height": "100px",
    "fontSize": "16px",
    "color": "#ccc",
    }
   =```
   => <pre><code><br>{<br>  "width": "100px",<br>  "height": "100px",<br>  "fontSize": "16px",<br>  "color": "#ccc",<br>}<br></code></pre>
  ```

### 未实现
- [ ] 列表语法
- [ ] 表格语法
- [x] 内嵌HTML
- [ ] 转义字符
- [ ] 脚注
