# docker-imapfilter

A forked small Docker image for running imapfilter from bbriggs/docker-imapfilter

### Create Container

`docker build -t anyone/imapfilter .`

### Usage

Modify the config.lua first

Fires a ( NOT a one-time ) run of imapfilter.
Every 60 seconds starts an imapfilter run.

`docker run -it -d -v $(pwd):/root/.imapfilter/ --name imapfilter anyone/imapfilter`
