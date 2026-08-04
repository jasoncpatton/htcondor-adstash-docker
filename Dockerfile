FROM python:3.13-slim-trixie
ARG HTCONDOR_RELEASE=25.x
ARG HTCONDOR_RELEASE_TYPE=release
ARG HTCONDOR_VERSION=25.8.2
ARG ELASTICSEARCHPY_VERSION=8.19.3

# set up adstash user
ENV ADSTASH_USER=adstash
ENV ADSTASH_HOME=/home/${ADSTASH_USER}
ENV ADSTASH_CONFIG=${ADSTASH_HOME}/adstash_config
ENV ADSTASH_PATH=/opt/condor_adstash
ENV ADSTASH_BIN=${ADSTASH_PATH}/bin
ENV ADSTASH_LIB=${ADSTASH_PATH}/lib
ENV ADSTASH_TIMEOUT=1200
ENV ADSTASH_ARGS=
RUN useradd -md ${ADSTASH_HOME} ${ADSTASH_USER}

# install system packages
RUN apt-get update && \
    apt-get install -y git curl supervisor && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# install external Python libraries
ADD requirements.txt /tmp/requirements.txt
RUN sed -i s/HTCONDOR_VERSION/${HTCONDOR_VERSION}/ /tmp/requirements.txt
RUN sed -i s/ELASTICSEARCHPY_VERSION/${ELASTICSEARCHPY_VERSION}/ /tmp/requirements.txt
RUN pip install --upgrade pip && \
    pip install --no-cache-dir -r /tmp/requirements.txt && \
    rm /tmp/requirements.txt
ENV CONDOR_PYTHON_LIB=

# install condor_adstash
ARG HTCONDOR_TARBALL=https://research.cs.wisc.edu/htcondor/tarball/${HTCONDOR_RELEASE}/${HTCONDOR_VERSION}/${HTCONDOR_RELEASE_TYPE}/condor-${HTCONDOR_VERSION}-src.tar.gz
ARG TMPDIR=/tmp/setup
COPY v25-preview.patch $TMPDIR/v25-preview.patch
RUN mkdir -p ${TMPDIR} ${ADSTASH_PATH}/bin ${ADSTASH_PATH}/lib && \
    curl -k -L ${HTCONDOR_TARBALL} > ${TMPDIR}/htcondor.tar.gz && \
    tar -xf ${TMPDIR}/htcondor.tar.gz --strip-components=1 --directory=${TMPDIR} && \
    git apply -v --directory ${TMPDIR} --unsafe-paths ${TMPDIR}/v25-preview.patch && \
    mv ${TMPDIR}/src/condor_scripts/condor_adstash ${ADSTASH_BIN} && \
    mv ${TMPDIR}/src/condor_scripts/adstash ${ADSTASH_LIB} && \
    rm -rf ${TMPDIR} && \
    chmod 0755 ${ADSTASH_BIN}/condor_adstash

# set up supervisord
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf
COPY exit_supervisord.sh /exit_supervisord.sh
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]

# add wrapper to checkpoint adstash to Elasticsearch
COPY adstash_checkpoint_wrapper.py ${ADSTASH_BIN}/adstash_checkpoint_wrapper.py
RUN chmod 0755 ${ADSTASH_BIN}/adstash_checkpoint_wrapper.py


# set up condor config
COPY adstash_config ${ADSTASH_CONFIG}
RUN chown ${ADSTASH_USER}:${ADSTASH_USER} ${ADSTASH_CONFIG}

# test imports
RUN PYTHONPATH=$PYTHONPATH:${ADSTASH_LIB}:${CONDOR_PYTHON_LIB} python -c "import htcondor2 as htcondor; import elasticsearch; import adstash"
