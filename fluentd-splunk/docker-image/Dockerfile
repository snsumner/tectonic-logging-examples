FROM fluent/fluentd:v0.12.33-debian

MAINTAINER Eduardo Silva <eduardo@treasure-data.com>
USER root
WORKDIR /home/fluent
ENV PATH /home/fluent/.gem/ruby/2.3.0/bin:$PATH

RUN buildDeps="sudo make gcc g++ libc-dev ruby-dev libffi-dev" \
     && apt-get update \
     && apt-get install \
     -y --no-install-recommends \
     $buildDeps \
    && echo 'gem: --no-document' >> /etc/gemrc \
    && gem install \
           fluent-plugin-record-reformer \
           fluent-plugin-kubernetes_metadata_filter \
           fluent-plugin-splunk-http-eventcollector \
           fluent-plugin-systemd \
    && gem install ffi \
    && SUDO_FORCE_REMOVE=yes \
    apt-get purge -y --auto-remove \
                  -o APT::AutoRemove::RecommendsImportant=false \
                  $buildDeps \
    && rm -rf /var/lib/apt/lists/* \
    && gem sources --clear-all \
    && rm -rf /tmp/* /var/tmp/* /usr/lib/ruby/gems/*/cache/*.gem

# Copy configuration files
COPY ./conf/fluent.conf /fluentd/etc/
COPY ./conf/kubernetes.conf /fluentd/etc/
COPY ./conf/systemd.conf /fluentd/etc/
COPY .conf/output.conf /fluentd/etc/


