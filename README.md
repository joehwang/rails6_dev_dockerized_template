
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

> Rails app / Webpacker / Live Reload / Sidekiq 使用同個image，只有啟動命令不同

![rails_ruby3_docker_flow.png](/Users/joehwang/Library/Mobile Documents/com~apple~CloudDocs/筆記/rails_ruby3_docker_flow.png)



## 目錄結構

```bash
├── databases #databases資料
│   ├── mongo_data
│   ├── mysql_data
│   └── pg_data
├── docker-compose.yml
├── .env #存放密碼等敏感資料，不要加入版本控制系統
├── nginx
│   ├── Dockerfile
│   ├── docker-entrypoint.sh
│   ├── letsencrypt #letsencrypt資料
│   ├── nginx.conf
│   └── nginx.template
├── rails_app
│   ├── Dockerfile
│   └── docker-entrypoint.sh
└── redis_data
```

## 1.建立Rails容器

**Dockfile**

```bash
FROM ruby:3.0.2-buster
ENV APP_PATH /rails_app
ENV BUNDLE_VERSION 2.1.4
ENV BUNDLE_PATH /usr/local/bundle/gems
ENV TMP_PATH /tmp/
ENV RAILS_LOG_TO_STDOUT true
ENV RAILS_PORT 3000
ENV TZ=Asia/Taipei
RUN echo $TZ | tee /etc/timezone
# copy entrypoint scripts and grant execution permissions
COPY ./docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh
RUN curl -sL https://deb.nodesource.com/setup_14.x | bash -
RUN curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg |  apt-key add -
RUN echo "deb https://dl.yarnpkg.com/debian/ stable main" |  tee /etc/apt/sources.list.d/yarn.list
# install dependencies for application
RUN apt update
RUN apt upgrade -y
RUN apt-get install -y --no-install-recommends apt-utils -y  \
git \
libxml2-dev \
libxslt-dev \
nodejs \
yarn \
imagemagick \
tzdata \
less \
vim \
&& rm -rf /var/cache/apk/* \
&& mkdir -p $APP_PATH 

RUN gem install bundler --version "$BUNDLE_VERSION" \
&& rm -rf $GEM_HOME/cache/*

# navigate to app directory
WORKDIR $APP_PATH

EXPOSE $RAILS_PORT

ENTRYPOINT [ "bundle", "exec" ]
```

**docker-entrypoint.sh**

`Dockerfile` 11 - 12 行會把`docker-entrypoint.sh` 複製至容器並賦予執行權限。

容器在啟動時自動執行docker-entrypoint.sh，用以判斷產生新rails專案或bundle install 更新 Gem。

>  新增gem只要更新Gemfile關掉容器再次重啟便自動安裝

```bash
#!/bin/bash
#檢查rails_app目錄中有沒有Gemfile
#
#沒有Gemfile : 
#  產生Gemfile加入rails安裝描述 e.g. gem 'rails','~>6.1.4',
#  執行bundle install 並 rails new 新專案
#
#有Gemfile : 
#  bundle install，刪掉server的pid

set -e
echo "Environment: $RAILS_ENV"
if [ -f "$APP_PATH/Gemfile"  ]
then
    echo "Gemfile exist!"
else
    echo "Generate Gemfile!"
    echo "source 'https://rubygems.org'" | tee $APP_PATH/Gemfile
    echo "gem 'rails', '~> $RAILS_VERSION'" >> $APP_PATH/Gemfile
    bundle install --jobs 20 --retry 5    
    bundle exec rails new $APP_PATH -f -d $DB_ADAPTER
fi

# install missing gems
bundle check || bundle install --jobs 20 --retry 5

# Remove pre-existing puma/passenger server.pid
rm -f $APP_PATH/tmp/pids/green.pid

echo "Start rails app"
# run passed commands
bundle exec ${@}
```

**docker-compose.yml**

第5行`volumes`設定了兩個讓容器間共用的volume，容器共享gem folder節省磁碟空間shared_data同理。

`services`區塊內描述容器的名稱和設定

下面的設定中描述`rails_app`容器dockerfile的位置，編譯完成的image名稱

volumes有哪些路徑，啟動的指令 etc ...

environment的`DB_ADAPTER`及`RAILS_VERSION`

用於rails new新專案時指定資料庫與rails版本

```yaml
version: "3.2"
networks:
  dev:

volumes:
  gem_cache:
  shared_data:

services:
  rails_app:
    build:
      context: ./rails_app
      dockerfile: Dockerfile
    image: joehwang/@rails6_dev_dockerized_template
    volumes:
      - shared_data:/var/shared
      - gem_cache:/usr/local/bundle/gems
      - ./rails_app:/rails_app
    ports:
      - 3303:3303
    stdin_open: true #容器標準輸入保持開啟
    tty: true #要docker分配虛擬終端綁到容器標準輸出入
    entrypoint: docker-entrypoint.sh
    command: bundle exec rails server -p 3303 -b 0.0.0.0 --pid ./tmp/pids/green.pid -e development #啟動rails server

    environment:
      RAILS_ENV: development
      DB_ADAPTER: sqlite3 # mysql, postgresql, sqlite3, oracle, sqlserver, jdbcmysql, jdbcsqlite3, jdbcpostgresql, jdbc #指定db
      RAILS_VERSION: 6.1.4 #指定rails版本
    networks:
      - dev
    env_file:
      - ".env"
```

接著在command line輸入`docker-compose build rails_app`製作docker image

> 為方便測試，DB_ADAPTER先設為sqlite3

> 每次修改完**docker-entrypoint.sh**要重build，讓修改後的docker-entrypoint複製到image

![](/Users/joehwang/Library/Application Support/marktext/images/2021-09-01-14-22-39-image.png)

image 成功編譯後，試試能不能跑起來。

# `docker-compose up rails_app`

瀏覽器輸入 http://localhost:3303

![](/Users/joehwang/Library/Application Support/marktext/images/2021-09-01-14-29-14-image.png)

> rails容器成功運行畫面，帥!

# 2.Rails容器接上mysql

這裡的db可自由換成postgresql / sqlite3 / mongodb 等 rails支援的資料庫軟體

資料庫的帳號密碼以環境變數方式讀取，以下使用mysql示範。

#### step2-1

回復rails_app資料夾只留Dockerfile與docker-entrypoint.sh

```bash
├── rails_app
│   ├── Dockerfile
│   └── docker-entrypoint.sh
```

#### step2-2

docker-compose.yml > services > rails_app > DB_ADAPTER

`sqlite3 改為 mysql`

#### step2-3

在terminal下`docker-compose up`，重新產生rails專案結構

> 這時候如果興沖沖的開
> 
> [http://localhost:3303](http://localhost:3303) 看測試頁面會看到

![](/Users/joehwang/Library/Application Support/marktext/images/2021-09-01-15-34-15-image.png)

> mysql的容器 / rails設定都沒做, 當然連不上啦

#### step2-4

在`docker-compose.yml`加上mysql容器設定

```yaml
version: "3.2"
networks:
  dev:

volumes:
  gem_cache:
  shared_data:

services:
  db: #執行mysql的容器名稱叫db，設定configs/database.yml時會用到

    image: mysql:5.7.22
    volumes:
      - ./databases/mysql_data:/var/lib/mysql
    ports:
      - 3306:3306
    networks:
      - dev
    env_file:
      - ".env"

  rails_app:
  #下略
```

#### step2-5

建立`.env`檔案至目錄

> .env**不要**放到版本控制系統

```bash
MYSQL_ROOT_PASSWORD=123456789 #沿用mysql官方image的密碼環境變數名稱
 MYSQL_PASSWORD=123456789 # 沿用mysql官方image的密碼環境變數名稱
 REDIS_URI=redis://redis:6379/0 #redis用
 REDIS_PASSWORD=123456789 #redis
 SECRET_KEY_BASE=8888875a497787c71da9a9bb03925ba2af4de8e1f6968bfcfe80fbfad7994b4ab22b71b42c8e72e060c72d53fe40711d03e0bf15f3b7170a49d173469ea487540 #rails secret key
 RAILS_ENV=development
 NODE_ENV=development
 WEBPACKER_DEV_SERVER_HOST=webpacker #webpacker dev server位置指向webpacker容器
```

#### step2-6

編輯`configs/database.yml`

```yaml
# MySQL. Versions 5.5.8 and up are supported.
#
# Install the MySQL driver
#   gem install mysql2
#
# Ensure the MySQL gem is defined in your Gemfile
#   gem 'mysql2'
#
# And be sure to use new-style password hashing:
#   https://dev.mysql.com/doc/refman/5.7/en/password-hashing.html
#
default: &default
  adapter: mysql2
  encoding: utf8mb4
  pool: <%= ENV.fetch("RAILS_MAX_THREADS") { 5 } %>
  username: root
  password: <%= ENV.fetch("MYSQL_ROOT_PASSWORD") %> #透過env取得密碼
  host: db #host指向容器名稱db，

development:
  <<: *default
  database: rails_app_development

# 下略
```

#### step2-7

`docker-compose down`**關掉rails_app容器**

`docker-compose up rails_app db`**啟動rails_app與mysql容器**

瀏覽http://localhost:3303

![](/Users/joehwang/Library/Application Support/marktext/images/2021-09-02-15-09-45-image.png)

database尚未建立XD

輸入`docker-compose exec rails_app bundle exec rake db:setup` **生成資料庫**

刷新頁面後可再次看到歡迎頁面

![2021-09-02-15-16-45-image.png](/Users/joehwang/Library/Application Support/marktext/images/2021-09-02-15-16-45-image.png)

# 3.加入Webpacker容器編譯 Tailwind CSS

[Webpacker](https://github.com/rails/webpacker)  rails整合Webpack的gem，rails 5.x之後已預設開啟

[Tailwind CSS](https://tailwindcss.tw) 很棒的Utility CSS框架，有3個特色我很欣賞

- 無需命名class name

- 後處理器*PostCSS*可以處理掉Utility CSS檔案肥大的問題

- 新增的JIT模式可以直接在classname上處理客製，非常方便 e.g. 寬度客製20px把classname命名為**w-[20px]** 即可，無需編輯tailwind.config.js

> 作者出的TailwindCSS UI有多種元件樣式可套，並同時支援css / Vue /React，大推
> 
> https://tailwindui.com

> Utility類型的CSS框架讓人卻步的class名稱查詢，vscode plugin解決了。

### step3-1

在`dockerc-compose.yml`加上容器設定

image和rails_app一樣是同一份

容器不引入`.env`，獨自設定

```yaml
  #前略
  webpacker:
    image: joehwang/rails6_dev_dockerized_template
    command: ruby bin/webpack-dev-server
    volumes:
      - shared_data:/var/shared
      - gem_cache:/usr/local/bundle/gems
      - ./rails_app:/rails_app
    environment:
      - NODE_ENV=development
      - RAILS_ENV=development
      - WEBPACKER_DEV_SERVER_HOST=0.0.0.0
    ports:
      - "3035:3035"
    networks:
      - dev
  #後略
```

修改rails_app/Gemfile將webpacer升到5.4

`gem 'webpacker', '~> 5.0'`

修改為

`gem 'webpacker', '~> 5.4'`

```bash
#執行bundle update，實行升級
docker-compose run webpacker bundle exec bundle update webpacker 
#移掉預設的webpacker
docker-compose run webpacker yarn remove @rails/webpacker
#裝5.4.0webpacker/postcss8
docker-compose run webpacker yarn add @rails/webpacker@5.4.0 @fullhuman/postcss-purgecss@^4.0.3 postcss@^8.2.10 postcss-loader@^4.0.3 sass@^1.32.7 autoprefixer@^10.2.6 

#[2021-09-03]目前 webpack-dev-server和Webpacker 5.x不相容。升到Webpacker 6 或 使用webpacker-dev-server 3.x 見 https://github.com/rails/rails/issues/43062
docker-compose run webpacker yarn remove webpack-dev-server
docker-compose run webpacker yarn add webpack-dev-server@3.11.2 --exact
```

輸入`docker-compose up webpacker`驗證webpack-dev-server結果

![](/Users/joehwang/Library/Application Support/marktext/images/2021-09-03-12-27-59-image.png)

> js編譯成功

### step3-2

安裝TailwindCSS

```bash
docker-compose run webpacker yarn add tailwindcss @tailwindcss/forms @tailwindcss/typography @tailwindcss/aspect-ratio @tailwindcss/typography @tailwindcss/line-clamp
```

建立stylesheet, import TailwindCSS

```bash
docker-compose run webpacker mkdir app/javascript/stylesheets 
docker-compose run webpacker touch app/javascript/stylesheets/application.scss
```

`app/javascript/stylesheets/application.scss`加入

```
@import "tailwindcss/base";
@import "tailwindcss/components";
@import "tailwindcss/utilities";
```

在`app/javascript/packs/application.js` import application.scss

```
import "stylesheets/application.scss"
```

rails_app資料夾的`postcss.config.js`引入 TailwindCSS  

```js
require('tailwindcss'),module.exports = {
  plugins: [
    require("tailwindcss"), //add this
    require("postcss-import"),
    require("postcss-flexbugs-fixes"),
    require("postcss-preset-env")({
      autoprefixer: {
        flexbox: "no-2009",
      },
      stage: 3,
    }),
  ],
};
```

app/javascript/packs/application.js加到`app/views/layouts/application.html.erb`  

```erb
<%= stylesheet_pack_tag 'application', 'data-turbolinks-track': 'reload' %>
```

**初始化TailwindCSS設定**

以下指令會在rails_app目錄加上tailwindcss設定

`--full`會帶出TailwindCSS class名稱與值方便客製

```
docker-compose run webpacker npx tailwindcss init --full
```

**打開JIT模式**

編輯`tailwind.config.js`加入`mode: "jit",`

![](/Users/joehwang/Library/Application Support/marktext/images/2021-09-03-13-11-29-image.png)

**設定purge**

當env為production 或 staging

TailwindCSS只打包**content**路徑**檔案中的CSS Class名稱**。

```
purge: {
enabled: ["production", "staging"].includes(process.env.NODE_ENV),
content: [
  './app/views/**/*.html.erb',
  './app/helpers/**/*.rb',
  './app/javascript/**/*.js',
],
},
```

![](/Users/joehwang/Library/Application Support/marktext/images/2021-09-03-13-20-58-image.png)

**設定babel.config.js**

**plugins**區塊加上

```js
//上略
'@babel/plugin-transform-runtime',
{
  helpers: false,
  regenerator: true,
  corejs: false
}
```

```js
['@babel/plugin-proposal-private-methods', { loose: true }]
```

檔案看起來像這樣

```js
module.exports = function (api) {
  var validEnv = ["development", "test", "production"];
  var currentEnv = api.env();
  var isDevelopmentEnv = api.env("development");
  var isProductionEnv = api.env("production");
  var isTestEnv = api.env("test");

  if (!validEnv.includes(currentEnv)) {
    throw new Error(
      "Please specify a valid `NODE_ENV` or " +
        '`BABEL_ENV` environment variables. Valid values are "development", ' +
        '"test", and "production". Instead, received: ' +
        JSON.stringify(currentEnv) +
        "."
    );
  }

  return {
    presets: [
      isTestEnv && [
        "@babel/preset-env",
        {
          targets: {
            node: "current",
          },
        },
      ],
      (isProductionEnv || isDevelopmentEnv) && [
        "@babel/preset-env",
        {
          forceAllTransforms: true,
          useBuiltIns: "entry",
          corejs: 3,
          modules: false,
          exclude: ["transform-typeof-symbol"],
        },
      ],
    ].filter(Boolean),
    plugins: [
      "babel-plugin-macros",
      "@babel/plugin-syntax-dynamic-import",
      isTestEnv && "babel-plugin-dynamic-import-node",
      "@babel/plugin-transform-destructuring",
      [
        "@babel/plugin-proposal-class-properties",
        {
          loose: true,
        },
      ],
      [
        "@babel/plugin-proposal-object-rest-spread",
        {
          useBuiltIns: true,
        },
      ],
      [
        "@babel/plugin-transform-runtime",
        {
          helpers: false,
          regenerator: true,
          corejs: false,
        },
      ],
      [
        "@babel/plugin-transform-regenerator",
        {
          async: false,
        },
      ],
      ["@babel/plugin-proposal-private-methods", { loose: true }],
    ].filter(Boolean),
  };
};
```

設定**config/webpack/environment.js**

```js
const { environment } = require("@rails/webpacker");
// Get the actual sass-loader config
const sassLoader = environment.loaders.get("sass");
const sassLoaderConfig = sassLoader.use.find(function (element) {
  return element.loader == "sass-loader";
});

// Use Dart-implementation of Sass (default is node-sass)
const options = sassLoaderConfig.options;
options.implementation = require("sass");

function hotfixPostcssLoaderConfig(subloader) {
  const subloaderName = subloader.loader;
  if (subloaderName === "postcss-loader") {
    subloader.options.postcssOptions = subloader.options.config;
    delete subloader.options.config;
  }
}

environment.loaders.keys().forEach((loaderName) => {
  const loader = environment.loaders.get(loaderName);
  loader.use.forEach(hotfixPostcssLoaderConfig);
});
module.exports = environment;
```

TailwindCSS設定告一段落，測試吧!

**新增controller start和action index**

```ruby
docker-compose run rails_app rails g controller Start index 
```

**在config/routes.rb加上**

```erb
root 'start#index'
```

編輯`app/views/start/index.html.erb`

```erb
<div class="p-6 max-w-sm mx-auto bg-white rounded-xl shadow-md flex items-center space-x-4">
  <div class="flex-shrink-0">

  </div>
  <div>
    <div class="text-xl font-medium text-black">ChitChat</div>
    <p class="text-gray-500">You have a new message!</p>
  </div>
</div>
```

啟動容器後訪問

http://localhost:3303

```bash
 docker-compose up rails_app db webpacker
```

![](/Users/joehwang/Library/Application Support/marktext/images/2021-09-03-14-40-30-image.png)

> TailwindCSS的設定告一段落。
> 
> 而且webpacker-dev-server讓頁面修改後自動刷新

> 若要裝VUE 或 React
> 
> docker-compose run webpacker rake webpacker:install:react
> 
> docker-compose run webpacker rake webpacker:install:vue
> 
> 不過babel.config.js會被override,再照上面設定一次就行。

# 4.加入Redis與Sidekiq

Sidekiq是Rails生態系中常用的非同步工作解決方案，相依於Redis

**step4-1**

**安裝Redis，透過.env file將redis的密碼帶進command**

```bash
  redis:
    image: redis
    command: [
        "bash",
        "-c",
        "
        docker-entrypoint.sh
        --requirepass ${REDIS_PASSWORD}
        ",
      ]
    ports:
      - "6380:6380"
    volumes:
      - ./redis_data:/data
    networks:
      - dev
    env_file:
      - ".env"
```

`docker-compose up redis`測試

![](/Users/joehwang/Library/Application Support/marktext/images/2021-09-04-08-56-08-image.png)

> redis啟動成功

**step4-2**

**安裝sidekiq**

編輯`rails_app/Gemfile`

```ruby
gem 'sidekiq'
```

**安裝gem**

`docker-compose run rails_app bundle exec bundle install`

**加入 sidekiq 設定檔**

`rails_app/config/sidekiq.yml`

```yaml
# Sample configuration file for Sidekiq.
# Options here can still be overridden by cmd line args.
# Place this file at config/sidekiq.yml and Sidekiq will
# pick it up automatically.
---
:verbose: false
:concurrency: 10
:timeout: 25

# Sidekiq will run this file through ERB when reading it so you can
# even put in dynamic logic, like a host-specific queue.
# http://www.mikeperham.com/2013/11/13/advanced-sidekiq-host-specific-queues/
:queues:
  - critical
  - default
  - <%= `hostname`.strip %>
  - low

# you can override concurrency based on environment
production:
  :concurrency: 25
staging:
  :concurrency: 15
```

**加入sidekiq連接Redis設定**

`rails_app/config/initializers/sidekiq.rb`

```rb
Sidekiq.configure_server do |config|
  config.redis = { url: ENV.fetch("REDIS_URI"), password: ENV.fetch("REDIS_PASSWORD") }
end

Sidekiq.configure_client do |config|
  config.redis = { url: ENV.fetch("REDIS_URI"), password: ENV.fetch("REDIS_PASSWORD") }
end
```

**編輯docker-compose.yml加上sidekiq容器**

```yml
  #前略
  sidekiq:
    container_name: sidekiq
    depends_on:
      - redis
    image: joehwang/rails6_dev_dockerized_template
    command: bundle exec sidekiq -C ./config/sidekiq.yml -e development

    working_dir: /rails_app
    volumes:
      - shared_data:/var/shared
      - gem_cache:/usr/local/bundle/gems
      - ./rails_app:/rails_app
    env_file:
      - ".env"
    networks:
      - dev
 #後略
```

**修改rails預設的active_job adapter**

`rails_app/config/application.rb`:

```ruby
class Application < Rails::Application
  # ...
  config.active_job.queue_adapter = :sidekiq
end
```

**測試**

`docker-compose up sidekiq`

![](/Users/joehwang/Library/Application Support/marktext/images/2021-09-04-09-42-24-image.png)

> Sidekiq 設定完成

# 5.設定Nginx與Lets Encrypt

Nginx和Lets Encrypt的CertBot會合併在同個容器

以下使用CertBot的standalone模式進行認證，請將網域設定A record指向

目前的外部IP，如果環境中有IP分享器要把80 / 443 port forward到機器的內部IP

```bash
#...
├── nginx
│ ├── Dockerfile
│ ├── docker-entrypoint.sh
│ ├── letsencrypt #letsencrypt資料
│ ├── nginx.conf
│ └── nginx.template
#...
```

### step 5-1

**編輯檔案內容**

**Dockerfile**

以nginx image為基底加上certbot，在cronjob中加上renew ssl的排程

做docker-entrypoint.sh複製，並給執行權限

```bash
FROM nginx:stable
RUN  apt-get update \
      && apt-get install -y cron certbot python-certbot-nginx bash wget \
      && rm -rf /var/lib/apt/lists/* \
      && echo "PATH=$PATH" > /etc/cron.d/certbot-renew  \
      && echo "@monthly certbot renew --nginx >> /var/log/cron.log 2>&1" >>/etc/cron.d/certbot-renew \
      && crontab /etc/cron.d/certbot-renew
COPY ./docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh
VOLUME /etc/letsencrypt
```

**docker-entrypoint.sh**

當容器開始執行，檢查`/etc/letsencrypt/live/`中有無**對應網址**資料夾

沒有資料夾certbot 已 standalone 模式進行驗證

否則編輯nginx.conf並啟動nginx

```bash
#!/bin/sh
set -e
echo "Your domain list: $DOMAIN_LIST"
cp /tmp/default.conf /tmp/$NGINX_HOST.conf
if [ -d "/etc/letsencrypt/live/$NGINX_HOST" ]
then
    echo "Let's Encrypt SSL already setup."
    sed -i -e 's/###//g' /tmp/$NGINX_HOST.conf
    envsubst '${NGINX_HOST}' < /tmp/$NGINX_HOST.conf > /etc/nginx/conf.d/default.conf 
    nginx -g 'daemon off;'
else
    echo "Applying for a SSL Certificate from Let's Encrypt"
    certbot certonly --standalone $CERTBOT_TEST_MODE --email $CERTBOT_EMAIL --agree-tos --preferred-challenges http -n -d $DOMAIN_LIST
    echo "Restart NGINX container !"
fi

exec "$@"
```

**nginx.conf**

```bash
user  nginx;
worker_processes  1;

error_log  /var/log/nginx/error.log warn;
pid        /var/run/nginx.pid;


events {
    worker_connections  1024;
}

http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;

    log_format  main  '$remote_addr - $remote_user [$time_local] "$request" '
                      '$status $body_bytes_sent "$http_referer" '
                      '"$http_user_agent" "$http_x_forwarded_for"';

    access_log  /var/log/nginx/access.log  main;
    sendfile        on;
    keepalive_timeout  60;
    gzip  on;
    proxy_buffer_size  128k;
    proxy_buffers   32 32k;
    proxy_busy_buffers_size 128k;
    include /etc/nginx/conf.d/*.conf;
}
```

**nginx.template**

由###開頭的字串標示需要後處理的地方，docker-entrypoint.sh使用sed做編輯

```bash
upstream green {server rails_app:3303;}

server {
  listen 80;
  ###listen 443 ssl http2;
  client_max_body_size 1G;
  server_name ${NGINX_HOST};
  if ($scheme = http) {
   return 301 https://$host$request_uri;
  }
  root /web_data/rails_app/public;
  try_files $uri/index.html $uri @rails;
  keepalive_timeout 10;

  ###ssl_certificate    /etc/letsencrypt/live/${NGINX_HOST}/fullchain.pem;
  ###ssl_certificate_key    /etc/letsencrypt/live/${NGINX_HOST}/privkey.pem;

  access_log /web_data/rails_app/log/nginx.access.log;
  error_log /web_data/rails_app/log/nginx.error.log;
  location /.well-known/acme-challenge {
    root /var/www/certbot;
  }
  # deny requests for files that should never be accessed
  location ~ /\. {
    deny all;
  }

  location ~* ^.+\.(rb|log)$ {
    deny all;
  }

  location @rails {

    real_ip_header X-Forwarded-For;
    proxy_set_header X-Forwarded-Proto https;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header Host $http_host;
    proxy_redirect off;
    proxy_pass http://green;


  }

   location ~* \.(woff|ttf|svg|woff2)$ {
     expires 1M;
     access_log off;
     add_header "Access-Control-Allow-Origin" "*";
     add_header Cache-Control public;
   }

  location ^~ /assets/ {
    gzip_static on;
    expires max;
    add_header Cache-Control public;
  }


  location = /50x.html {
    root html;
  }

  location = /404.html {
    root html;
  }
}

server {
        server_name www.${NGINX_HOST};
        return 301 $scheme://${NGINX_HOST}$request_uri;
}
```

### step 5-2

**在docker-compose.yml加上nginx容器**

在environment的區塊中填入網址

`CERTBOT_TEST_MODE`參數在確認運行成功後再註解掉

因為letsencrypt有申請憑證的限制。

```yml
 #...
  web_serv:

    build:
      context: ./nginx
      dockerfile: Dockerfile
    entrypoint: docker-entrypoint.sh
    volumes:
      - ./nginx/nginx.template:/tmp/default.conf:ro
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf:rw
      - ./:/web_data
      - ./nginx/letsencrypt:/etc/letsencrypt
    ports:
      - "30304:80"
      - "30305:443"
    depends_on:
      - rails_app
    environment:
      - NGINX_HOST=17line.xyz
      - DOMAIN_LIST=17line.xyz,api.17line.xyz
      - NGINX_PORT=80
      - CERTBOT_EMAIL=joehwang.com@gmail.com
      - CERTBOT_TEST_MODE=--test-cert #option
    networks:
      - dev
   #...
```

### step 5-3

測試!

`docker-compose up web_serv`

![](/Users/joehwang/Library/Application Support/marktext/images/2021-09-04-17-39-13-image.png)

> image編譯完成，SSL申請成功



# 最後驗收!啟動所有服務

確認ssl申請成功後

- 清空**nginx/letsencrypt**資料夾內容

- 註解**docker-compose.yml > web_serv > CERTBOT_TEST_MODE**

- `rails_app/config/application.rb`將網或加入rails

![](/Users/joehwang/Library/Application Support/marktext/images/2021-09-04-18-10-09-image.png)



**docker-compose up** 啟動所有服務

![](/Users/joehwang/Library/Application Support/marktext/images/2021-09-04-18-12-46-image.png)

> 搞定收工!

# 結語

這個作法可以製作出易於攜帶和擴展的環境相比VM輕巧許多

進行開發的時候安裝各種軟體也不會汙染環境，也能為系統

轉換為K8S做準備。推薦給有相似需求的朋友。 



# 參考連結

[1]  Rails 6 Development With Docker

https://betterprogramming.pub/rails-6-development-with-docker-55437314a1ad

[2] Rails 6.1, TailwindCSS JIT, Webpacker & PostCSS 8

https://davidteren.medium.com/rails-6-1-tailwindcss-jit-webpacker-postcss-8-16e03dbaebe1

[3]  How to use Let's Encrypt DNS challenge validation?

https://serverfault.com/questions/750902/how-to-use-lets-encrypt-dns-challenge-validation

[4] Nginx and Let’s Encrypt with Docker in Less Than 5 Minutes

https://pentacent.medium.com/nginx-and-lets-encrypt-with-docker-in-less-than-5-minutes-b4b8a60d3a71


