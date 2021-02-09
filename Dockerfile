FROM python:3.9-slim
ARG HTCONDOR_VERSION=master
ARG ADSTASH_PATH=/opt/condor_adstash

# install external Python libraries
# (try to get matching version of HTCondor if possible)
ADD requirements.txt /.
RUN pip install --no-cache-dir htcondor==$HTCONDOR_VERSION || true && \
    pip install --no-cache-dir -r requirements.txt && \
    rm requirements.txt

# install curl
RUN apt-get update && \
    apt-get install -y curl && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# install condor_adstash from the source tree
RUN mkdir -p $ADSTASH_PATH/bin $ADSTASH_PATH/lib && \
    [ "$HTCONDOR_VERSION" = "master" ] && TAG="" || TAG=V$(echo $HTCONDOR_VERSION | sed 's/\./_/g') && \
    curl -k -L https://api.github.com/repos/htcondor/htcondor/tarball/$TAG > /tmp/htcondor.tar.gz && \
    tar -xf /tmp/htcondor.tar.gz --strip-components=1 --directory=/tmp && \
    mv /tmp/src/condor_scripts/condor_adstash $ADSTASH_PATH/bin && \
    mv /tmp/src/condor_scripts/adstash $ADSTASH_PATH/lib && \
    rm -rf /tmp/* && \
    chmod u+x $ADSTASH_PATH/bin/condor_adstash

# set PYTHONPATH to pickup adstash library
ENV PYTHONPATH "$PYTHONPATH:$ADSTASH_PATH/lib"

# test imports
RUN mkdir -p /etc/condor && \
    touch /etc/condor/condor_config && \
    python -c "import htcondor; import elasticsearch; import adstash"

# run adstash in standalone mode
CMD ["$ADSTASH_PATH/bin/condor_adstash", "--standalone"]