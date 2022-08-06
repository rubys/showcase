FROM phusion/passenger-full:2.3.0

RUN rm /etc/nginx/sites-enabled/default
RUN rm -f /etc/service/nginx/down
RUN rm -f /etc/service/redis/down

USER app
RUN mkdir /home/app/showcase
WORKDIR /home/app/showcase

ENV RAILS_ENV=production
ENV BUNDLE_WITHOUT="development test"
COPY --chown=app:app Gemfile Gemfile.lock .
RUN bundle install
COPY --chown=app:app . .

RUN SECRET_KEY_BASE=`bin/rails secret` \
  bin/rails assets:precompile

USER root
CMD ["/sbin/my_init"]
