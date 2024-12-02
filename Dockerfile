#
# Basic Parameters
#
ARG PUBLIC_REGISTRY="public.ecr.aws"
ARG ARCH="x86_64"
ARG OS="linux"
ARG VER="4.19.4"
ARG PKG="samba"

ARG BASE_REGISTRY="${PUBLIC_REGISTRY}"
ARG BASE_REPO="arkcase/base"
ARG BASE_VER="8"
ARG BASE_VER_PFX=""
ARG BASE_IMG="${BASE_REGISTRY}/${BASE_REPO}:${BASE_VER_PFX}${BASE_VER}"

#
# To build the RPMs
#
FROM "${BASE_IMG}" AS builder

#
# Basic Parameters
#
ARG ARCH
ARG OS
ARG VER
ARG PKG
ARG BASE_VER

#
# Some important labels
#
LABEL ORG="ArkCase LLC"
LABEL MAINTAINER="ArkCase Support <support@arkcase.com>"
LABEL APP="Samba RPM Builder"
LABEL VERSION="${VER}"

#
# Full update
#
RUN yum -y install epel-release
RUN yum -y update
RUN yum -y install yum-utils rpm-build which

#
# Enable the required repositories
#
RUN yum-config-manager \
		--enable devel \
		--enable powertools

#
# Download the requisite SRPMs
#
WORKDIR /root/rpmbuild
RUN yum -y install wget
# First try the main repository
ENV REPO="https://dl.rockylinux.org/pub/rocky/${BASE_VER}/BaseOS/source/tree/Packages"
RUN wget --recursive --level 2 --no-parent --no-directories "${REPO}" --directory-prefix=. --accept "samba-*.src.rpm" --accept "libldb-*.src.rpm" || true
# Now try the vault repository
ENV REPO="https://dl.rockylinux.org/vault/rocky/${BASE_VER}/BaseOS/source/tree/Packages"
RUN wget --recursive --level 2 --no-parent --no-directories "${REPO}" --directory-prefix=. --accept "samba-*.src.rpm" --accept "libldb-*.src.rpm" || true
ENV REPO=""
COPY find-latest-srpm .
COPY get-dist .

#
# We have the RPMs available, now find the latest ones and build them
#

#
# Build the one missing build dependency - python3-ldb-devel
#
RUN LIBLDB_SRPM="$( ./find-latest-srpm libldb-*.src.rpm )" && \
    if [ -z "${LIBLDB_SRPM}" ] ; then echo "No libldb SRPM was found" ; exit 1 ; fi && \
    yum-builddep -y "${LIBLDB_SRPM}" && \
    rpmbuild --clean --rebuild "${LIBLDB_SRPM}"

#
# Create a repository that facilitates installation later
#
RUN yum -y install createrepo
RUN mkdir -p RPMS && createrepo RPMS
COPY arkcase.repo /etc/yum.repos.d
RUN ln -svf $(readlink -f RPMS) /rpm

RUN yum -y install python3-ldb python3-ldb-devel

#
# Build Samba now
#
RUN SAMBA_SRPM="$( ./find-latest-srpm samba-*.src.rpm )" && \
    if [ -z "${SAMBA_SRPM}" ] ; then echo "No Samba SRPM was found" ; exit 1 ; fi && \
    yum-builddep -y "${SAMBA_SRPM}" && \
    yum -y install \
		bind \
		krb5-server \
		ldb-tools \
		python3-cryptography \
		python3-iso8601 \
		python3-markdown \
		python3-pyasn1 \
		python3-setproctitle \
		tdb-tools && \
    DIST="$( ./get-dist "${SAMBA_SRPM}" )" && \
    if [ -z "${DIST}" ] ; then echo "Failed to identify the distribution for the SRPM [${SAMBA_SRPM}]" ; exit 1 ; fi && \
    rpmbuild --clean --define "dist .${DIST}" --define "${DIST} 1" --with dc --rebuild "${SAMBA_SRPM}"
RUN rm -rf RPMS/repodata
RUN mkdir -p RPMS && createrepo RPMS

#
# Create an empty image just with the RPMS directory
#
FROM scratch

COPY --from=builder /root/rpmbuild/RPMS /rpm
