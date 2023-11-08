FROM registry.redhat.io/rhel9/python-311

COPY . /opt/app-root/src
RUN mkdir /tmp/bin && curl https://github.com/jqlang/jq/releases/download/jq-1.6/jq-linux64 > /tmp/bin/jq && \
    chmod 755 /tmp/bin/jq && mkdir /tmp/oc && \
    curl -L https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/stable/openshift-client-linux.tar.gz > /tmp/oc/openshift-client-linux.tar.gz && \
    tar xvf /tmp/oc/openshift-client-linux.tar.gz && cd /tmp/oc/ && mv oc /tmp/bin/oc && export PATH=$PATH:/tmp/bin/ && python3 -m pip install analytics
