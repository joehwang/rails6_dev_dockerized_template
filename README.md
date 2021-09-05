
## 前言

工作場景需要在Windows / OSX 交互開發

容器啟動輕便與環境文件化(*Dockerfile*)的特性，

節省不少設定環境的時間心力並確保團隊開發環境一致。

#### 目標

- rails / nginx / mysql 各自為獨立容器

- 檔案編輯後頁面自動刷新

- 可以透過https網址存取

- 可以用TailwindCSS

### 環境

macOS Big Sur 11.5.2

windows 11 WSL2

### TechStack

- Ruby 3.0

- Rails 6.1.4

- Nginx

- Lets Encrypt

- MySQL

- Redis

- Sidekiq

- Webpacker

- TailwindCSS

## 思路

Nginx和Lets Encrypt的CertBot放在同個容器處理https，流量導到Rails app容器

Webpacker容器編譯 JS/SCSS 的修改，LiveReload更新檔案後刷新瀏覽器頁面

Sidekiq為佇列服務與Redis搭配

詳細解說見medium: https://medium.com/@joehwang.com/rails%E9%96%8B%E7%99%BC%E7%92%B0%E5%A2%83%E5%AE%B9%E5%99%A8%E5%8C%96-505dba2c9678


# 參考連結

[1]  Rails 6 Development With Docker

https://betterprogramming.pub/rails-6-development-with-docker-55437314a1ad

[2] Rails 6.1, TailwindCSS JIT, Webpacker & PostCSS 8

https://davidteren.medium.com/rails-6-1-tailwindcss-jit-webpacker-postcss-8-16e03dbaebe1

[3]  How to use Let's Encrypt DNS challenge validation?

https://serverfault.com/questions/750902/how-to-use-lets-encrypt-dns-challenge-validation

[4] Nginx and Let’s Encrypt with Docker in Less Than 5 Minutes

https://pentacent.medium.com/nginx-and-lets-encrypt-with-docker-in-less-than-5-minutes-b4b8a60d3a71


