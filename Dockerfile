FROM phusion/passenger-full:2.3.1

RUN rm /etc/nginx/sites-enabled/default
RUN rm -f /etc/service/nginx/down
RUN rm -f /etc/service/redis/down

RUN apt-get update; \
  apt-get dist-upgrade -y; \
  apt-get install -y apache2-utils wget rsync

RUN wget -q -O - https://dl-ssl.google.com/linux/linux_signing_key.pub | apt-key add - \ 
 && echo "deb http://dl.google.com/linux/chrome/deb/ stable main" >> /etc/apt/sources.list.d/google-chrome.list \
 && apt-get update && apt-get install -y google-chrome-stable

RUN echo 'env RAILS_MASTER_KEY;' >> /etc/nginx/main.d/default.conf

USER app
RUN mkdir /home/app/showcase
WORKDIR /home/app/showcase

ENV RAILS_ENV=production
ENV BUNDLE_WITHOUT="development test"
COPY --chown=app:app Gemfile Gemfile.lock ./
RUN bundle install
COPY --chown=app:app . .

RUN SECRET_KEY_BASE=`bin/rails secret` \
  bin/rails assets:precompile

USER root
CMD ["/home/app/showcase/bin/init"]
