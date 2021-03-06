#!/bin/sh
HELPERLIB_SH_SOURCE_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

function say {
  echo "==> $@"
}

function cosmic_sources_retrieve {
  BASEDIR=$1
  GITSSH=$2
  gitclone_recursive 'git@github.com:MissionCriticalCloud/cosmic.git' "${BASEDIR}/cosmic"  ${GITSSH}
}

function cosmic_microservices_sources_retrieve {
  BASEDIR=$1
  GITSSH=$2
  gitclone_recursive 'ssh://git@sbp.gitlab.schubergphilis.com:2228/MCC/cosmic-microservices.git' "${BASEDIR}/cosmic-microservices"  ${GITSSH}
}

function gitclone_recursive {
  REPO_URL=$1
  CHECKOUT_PATH=$2
  GIT_SSH=$3

  mkdir -p "${CHECKOUT_PATH}"
  if [ ! -d "${CHECKOUT_PATH}/.git" ]; then
    say "No git repo found at ${CHECKOUT_PATH}, cloning ${REPO_URL}"
  if [ -z ${GIT_SSH} ] || [ "${GIT_SSH}" -eq "1" ]; then
    git clone --recursive "${REPO_URL}" "${CHECKOUT_PATH}"
    else
      git clone `echo ${REPO_URL} | sed 's@git\@github.com:@https://github.com/@'` "${CHECKOUT_PATH}"
      cwd=$(pwd)
      cd "${CHECKOUT_PATH}"
      git submodule init
      sed -i 's@git\@github.com:@https://github.com/@' .git/config
      git submodule update
      cd "${cwd}"
    fi
    say "Please use 'git checkout' to checkout the branch you need."
  else
    say "Git repo already found at ${CHECKOUT_PATH}"
  fi
}

function gitclone {
  REPO_URL=$1
  CHECKOUT_PATH=$2
  GIT_SSH=$3
  mkdir -p "${CHECKOUT_PATH}"
  if [ ! -d "${CHECKOUT_PATH}/.git" ]; then
    say "No git repo found at ${CHECKOUT_PATH}, cloning ${REPO_URL}"
    if [ -z ${GIT_SSH} ] || [ "${GIT_SSH}" -eq "1" ]; then
      git clone "${REPO_URL}" "${CHECKOUT_PATH}"
    else
      git clone `echo ${REPO_URL} | sed 's@git\@github.com:@https://github.com/@'` "${CHECKOUT_PATH}"
    fi
    say "Please use 'git checkout' to checkout the branch you need."
  else
    say "Git repo already found at ${CHECKOUT_PATH}"
  fi
}

function wget_fetch {
  if [ ! -f "$2" ]; then
    say "Fetching $1"
    wget "$1" -O "$2"
  fi
}

function config_maven {
  if [ ! -f ~/.m2/settings.xml ]; then
    if [ ! -d ~/.m2 ]; then
      mkdir ~/.m2
    fi
    cp "${HELPERLIB_SH_SOURCE_DIR}/config/maven_settings.xml" ~/.m2/settings.xml
  fi
}

function install_kvm_packages {
  # Parameters
  hvip=$1
  hvuser=$2
  hvpass=$3

  if [  -d /data/git/$HOSTNAME/packaging/dist/rpmbuild/RPMS/x86_64 ]; then
    distdir=/data/git/$HOSTNAME/packaging/dist/rpmbuild/RPMS/x86_64
  else
    if [  -d ../dist/rpmbuild/RPMS/x86_64 ]; then
      distdir=../dist/rpmbuild/RPMS/x86_64
    fi
  fi

  say "Dist dir is ${distdir}"

  # SSH/SCP helpers
  ssh_base="sshpass -p ${hvpass} ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=quiet -t "
  scp_base="sshpass -p ${hvpass} scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=quiet "

  # scp packages to hypervisor, remove existing, then install new ones
  ${ssh_base} ${hvuser}@${hvip} rm cosmic-*
  ${scp_base} ${distdir}/* ${hvuser}@${hvip}:
  ${ssh_base} ${hvuser}@${hvip} yum -y remove cosmic-common
  ${ssh_base} ${hvuser}@${hvip} rm -f /etc/cosmic/agent/agent.properties
  ${ssh_base} ${hvuser}@${hvip} yum -y localinstall cosmic-agent* cosmic-common*
  # Use OVS networking
  ${ssh_base} ${hvuser}@${hvip} 'echo "libvirt.vif.driver=com.cloud.hypervisor.kvm.resource.OvsVifDriver" >> /etc/cosmic/agent/agent.properties'
  ${ssh_base} ${hvuser}@${hvip} 'echo "network.bridge.type=openvswitch" >> /etc/cosmic/agent/agent.properties'
  ${ssh_base} ${hvuser}@${hvip} 'echo "guest.cpu.mode=host-passthrough" >> /etc/cosmic/agent/agent.properties'
  ${ssh_base} ${hvuser}@${hvip} 'echo "guest.network.device=cloudbr0" >> /etc/cosmic/agent/agent.properties'
  ${ssh_base} ${hvuser}@${hvip} 'echo "public.network.device=pub0" >> /etc/cosmic/agent/agent.properties'
  ${ssh_base} ${hvuser}@${hvip} 'echo "private.network.device=cloudbr0" >> /etc/cosmic/agent/agent.properties'
  # Enable debug logging
  ${ssh_base} ${hvuser}@${hvip} sed -i 's/INFO/DEBUG/g' /etc/cosmic/agent/log4j-cloud.xml
  # Enable remote debugging
  ${ssh_base} ${hvuser}@${hvip} mkdir -p /etc/systemd/system/cosmic-agent.service.d/
  ${ssh_base} ${hvuser}@${hvip} 'printf "[Service]\nEnvironment=JAVA_REMOTE_DEBUG=-Xrunjdwp:transport=dt_socket,server=y,suspend=n,address=8000" > /etc/systemd/system/cosmic-agent.service.d/debug.conf'
  ${ssh_base} ${hvuser}@${hvip} systemctl daemon-reload
}

function clean_kvm {
  # Parameters
  hvip=$1
  hvuser=$2
  hvpass=$3

  # SSH/SCP helpers
  ssh_base="sshpass -p ${hvpass} ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=quiet -t "
  scp_base="sshpass -p ${hvpass} scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=quiet "

  # Clean KVM in case it has been used before
  ${ssh_base} ${hvuser}@${hvip} systemctl daemon-reload
  ${ssh_base} ${hvuser}@${hvip} systemctl stop cosmic-agent
  ${ssh_base} ${hvuser}@${hvip} systemctl disable cosmic-agent
  ${ssh_base} ${hvuser}@${hvip} systemctl restart libvirtd
  ${ssh_base} ${hvuser}@${hvip} sed -i 's/INFO/DEBUG/g' /etc/cosmic/agent/log4j-cloud.xml
  ${ssh_base} ${hvuser}@${hvip} "for host in \$(virsh list | awk '{print \$2;}' | grep -v Name |egrep -v '^\$'); do virsh destroy \$host; done"
}

function clean_xenserver {
  # Parameters
  hvip=$1
  hvuser=$2
  hvpass=$3

  /data/shared/helper_scripts/cleaning/xapi_cleanup_xenservers.py http://${hvip} ${hvuser} ${hvpass}

}

function parse_marvin_config {
  #Parameters
  marvinCfg=$1

  # Parse marvin config
  # This should be done in python instead,
  # for now we just hack the common usecase together

  # All we support is a single cluster with 1 or 2 hypervisors.

  # We grab some useful info from the supplied Marvin json file.

  # Zone name
  zone=$(cat ${marvinCfg} | grep -v "#" | python -c "
import sys, json
print json.load(sys.stdin)['zones'][0]['name']
  ")

  # Hypervisor type
  hypervisor=$(cat ${marvinCfg} | grep -v "#" | python -c "
import sys, json
print json.load(sys.stdin)['zones'][0]['pods'][0]['clusters'][0]['hypervisor'].lower()
  ")

  # Primary storage location
  primarystorage=$(cat ${marvinCfg} | grep -v "#" | python -c "
import sys, json
print json.load(sys.stdin)['zones'][0]['pods'][0]['clusters'][0]['primaryStorages'][0]['url']" | cut -d: -f3
  )

  secondarystorage=$(cat ${marvinCfg} | grep -v "#" | python -c "
import sys, json
print json.load(sys.stdin)['zones'][0]['secondaryStorages'][0]['url']" | cut -d: -f3
  )

  for i in 1 2 3 4 5 6 7 8 9
  do
  # username hypervisor i
  export hvuser${i}=$(cat ${marvinCfg} | grep -v "#" | python -c "
try:
  import sys, json
  print json.load(sys.stdin)['zones'][0]['pods'][0]['clusters'][0]['hosts'][${i}-1]['username']
except:
  print ''
  ")

  # password hypervisor i
  export hvpass${i}=$(cat ${marvinCfg} | grep -v "#" | python -c "
try:
  import sys, json
  print json.load(sys.stdin)['zones'][0]['pods'][0]['clusters'][0]['hosts'][${i}-1]['password']
except:
 print ''
  ")

  # ip adress hypervisor i
  export hvip${i}=$(cat ${marvinCfg} | grep -v "#" | python -c "
try:
  import sys, json
  print json.load(sys.stdin)['zones'][0]['pods'][0]['clusters'][0]['hosts'][${i}-1]['url']
except:
 print ''
  " | cut -d/ -f3)
  done

  for i in 1 2 3 4 5 6 7 8 9
  do
    # username cs i
    export cs${i}user=$(cat ${marvinCfg} | grep -v "#" | python -c "
try:
  import sys, json
  print json.load(sys.stdin)['mgtSvr'][${i}-1]['user']
except:
  print ''
")

    # password cs i
    export cs${i}pass=$(cat ${marvinCfg} | grep -v "#" | python -c "
try:
  import sys, json
  print json.load(sys.stdin)['mgtSvr'][${i}-1]['passwd']
except:
 print ''
")

    # ip adress cs i
    export cs${i}ip=$(cat ${marvinCfg} | grep -v "#" | python -c "
try:
  import sys, json
  print json.load(sys.stdin)['mgtSvr'][${i}-1]['mgtSvrIp']
except:
 print ''
")

    # hostname cs i
    export cs${i}hostname=$(cat ${marvinCfg} | grep -v "#" | python -c "
try:
  import sys, json
  print json.load(sys.stdin)['mgtSvr'][${i}-1]['mgtSvrName']
except:
 print ''
")
  csip=
  eval csip="\$cs${i}ip"
  if [ -v $( eval "echo \${cs${i}ip}" ) ]  || [ "${csip}" == "localhost" ]; then
    if [ ! -v $( eval "echo \${cs${i}hostname}" ) ]; then
      eval cshostname="\$cs${i}hostname"
      export cs${i}ip=$(getent hosts ${cshostname} | awk '{ print $1 }')
    fi
  fi
  done

  for i in 1 2 3 4 5 6 7 8 9
  do
    # ip address controller node i
    export nsx_controller_node_ip${i}=$(cat ${marvinCfg} | grep -v "#" | python -c "
try:
  import sys, json
  print json.load(sys.stdin)['niciraNvp']['controllerNodes'][${i}-1]
except:
 print ''
  " | cut -d/ -f3)
  done

  for i in 1 2 3 4 5 6 7 8 9
  do
    # ip address service node i
    export nsx_service_node_ip${i}=$(cat ${marvinCfg} | grep -v "#" | python -c "
try:
  import sys, json
  print json.load(sys.stdin)['niciraNvp']['serviceNodes'][${i}-1]
except:
 print ''
  " | cut -d/ -f3)
  done

  for i in 1 2 3 4 5 6 7 8 9
  do
    # ip address management node i
    export nsx_management_node_ip${i}=$(cat ${marvinCfg} | grep -v "#" | python -c "
try:
  import sys, json
  print json.load(sys.stdin)['niciraNvp']['managerNodes'][${i}-1]
except:
 print ''
  " | cut -d/ -f3)
  done
}

function marvin_build_and_install {
  cwd=$(pwd)

  # Marvin's root path
  build_dir=$1

  say "[MARVIN] Installing..."

  # Generate Cosmic API commands
  say "[MARVIN] Generating API commands..."
  cd "${build_dir}/marvin"
  rm -rf ./cloudstackAPI
  python codegenerator.py -s ../../cosmic-core/apidoc/target/commands.xml
  say "[MARVIN] API commands generated"

  # Back to Marvin's root path
  cd "${build_dir}"

  # Test Marvin
  say "[MARVIN] Starting tests..."
  nosetests -v --with-xunit tests

  # Create Marvin distribution package
  say "[MARVIN] Creating distribution package..."
  python setup.py sdist

  # Find out Marvin's version
  version=$(grep "VERSION = " setup.py | grep -o "'.*'" | sed "s/'//g")
  marvin_dist="dist/Marvin-${version}.tar.gz"

  # Locally install Marvin distribution package
  say "[MARVIN] Locally installing distribution package..."
  sudo pip install --upgrade ${marvin_dist} &> /dev/null
  sudo pip install nose --upgrade --force &> /dev/null

  say "[MARVIN] Successfully installed"
  cd "${cwd}"
}

function minikube_get_ip {
  # Get the IPv4 address from minikube
  eval $(minikube docker-env)
  export MINIKUBE_IP=`minikube ip`
  export MINIKUBE_HOST=${MINIKUBE_IP//./-}.cloud.lan
  say "Got minikube IP: ${MINIKUBE_IP}, Host: ${MINIKUBE_HOST}"
}

function minikube_stop {
  #Parameters
  local cleanup=$1

  # Start minikube
  if [ "${cleanup}" == "true" ]; then
   say "Stopping minikube with cleanup"
   minikube stop || true
   minikube delete || true
  else
   say "Stopping minikube without cleanup"
   minikube stop || true
  fi
}

function minikube_start {
  #Parameters
  local cleanup=$1

  # Start minikube
  if [ "${cleanup}" == "true" ]; then
   say "Starting minikube with cleanup"
   minikube_stop "true"
  else
   say "Starting minikube without cleanup"
  fi

  if [[ $(minikube status) =~ 'minikubeVM: Running' && $(minikube status) =~ 'localkube: Running' ]]; then 
    say "Minikube already running"
  else
    minikube start --vm-driver kvm --kvm-network NAT
  fi

  return $?
}

function cosmic_docker_registry {

    if [ -z $1 ]; then
      local cleanup="true"
    else
      local cleanup=$1
    fi

    if [ "${cleanup}" == "true" ]; then
        say "Generating certificates for registry"
        mkdir -p /tmp/registry/certs
        rm -f /tmp/registry/certs/*
        # Generate self-signed certificate
        openssl req -x509 -sha256 -nodes -newkey rsa:4096 -keyout /tmp/registry/certs/domain.key -out /tmp/registry/certs/domain.crt -days 365 -subj "/C=NL/ST=NH/L=AMS/O=SBP/OU=cosmic/CN=${MINIKUBE_HOST}" &> /dev/null
        # Add certificate to local trust store
        sudo cp /tmp/registry/certs/domain.crt /etc/pki/ca-trust/source/anchors/
        sudo update-ca-trust
        # Add certificate to the docker deamon (to trust)
        minikube ssh "sudo mkdir -p /etc/docker/certs.d/${MINIKUBE_HOST}:30081"
        cat /tmp/registry/certs/domain.crt | minikube ssh "sudo cat > ca.crt"
        minikube ssh "sudo mv ca.crt /etc/docker/certs.d/${MINIKUBE_HOST}:30081/ca.crt"
        minikube ssh "sudo /etc/init.d/docker restart"

        say "Uploading certificates as secrets"
        kubectl create secret generic registry-certs --from-file=/tmp/registry/certs/domain.crt --from-file=/tmp/registry/certs/domain.key --namespace=internal

        say "Starting deployment: registry"
        kubectl create -f /data/shared/deploy/cosmic/kubernetes/deployments/registry.yml

        say "Starting service: registry"
        kubectl create -f /data/shared/deploy/cosmic/kubernetes/services/registry.yml
    fi

    say "Waiting for registry service to be available."
    until [[ $(kubectl get deployment --namespace=internal registry -o custom-columns=:.status.AvailableReplicas) =~ 1 ]]; do echo -n .; sleep 1; done; echo ""
}


# Some convenient helper methods for container troubleshooting
function d_show_message_queue {
  if [ -z "${MINIKUBE_IP}" ]; then minikube_get_ip; fi
  echo "Show queues on ${MINIKUBE_IP}"
  curl -s -u root:password "http://${MINIKUBE_IP}:30101/api/queues?columns=name,messages,message_stats.publish,message_stats.deliver" | python -m json.tool
}

function d_show_usage {
  if [ -z "${MINIKUBE_IP}" ]; then minikube_get_ip; fi
  local STARTDATE=$(date +'%Y-%m-01')
  local ENDDATE=$(date +'%Y-%m-01' -d "${STARTDATE} +1 months")

  echo "Show usage (unfiltered) from ${STARTDATE} till ${ENDDATE}"
  curl http://${MINIKUBE_IP}:31011\?\from\=${STARTDATE}\&to\=${ENDDATE}
  echo ""
}

function d_show_elasticsearch_aggr_by_vm {
  if [ -z "${MINIKUBE_IP}" ]; then minikube_get_ip; fi

  if [ -z "${STARTDATE}" ]; then local STARTDATE=$(date +'%Y-%m-01'); fi
  if [ -z "${ENDDATE}" ]; then local ENDDATE=$(date +'%Y-%m-01' -d "${STARTDATE} +1 months"); fi
  echo "Show usage aggregated by VM from ${STARTDATE} till ${ENDDATE}"

  echo '{"query":{"bool":{"must":[{"range":{"@timestamp":{"gte":"STARTDATE","lt":"ENDDATE"}}},{"term":{"resourceType":"VirtualMachine"}}]}},"from":0,"size":0,"aggs":{"domains":{"terms":{"field":"domainUuid"},"aggs":{"virtualMachines":{"terms":{"field":"resourceUuid"},"aggs":{"states":{"terms":{"field":"payload.state"},"aggs":{"cpu":{"avg":{"field":"payload.cpu"}},"memory":{"avg":{"field":"payload.memory"}}}}}}}}}}' | \
  sed "s/STARTDATE/${STARTDATE}/g" | \
  sed "s/ENDDATE/${ENDDATE}/g" | \
  curl -s -X POST http://${MINIKUBE_IP}:30121/_search -d@- | python -m json.tool
}
