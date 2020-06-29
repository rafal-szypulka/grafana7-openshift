#!/bin/bash
# Deploy Grafana 7 on OpenShift 4
# Rafal Szypulka @ IBM

GRAFANA_NAMESPACE=grafana

echo "-> Create namespace ${GRAFANA_NAMESPACE}..."
oc create namespace ${GRAFANA_NAMESPACE}

echo "-> Copy OCP Prometheus dashboards to the ${GRAFANA_NAMESPACE} namespace..."
for i in `oc -n openshift-monitoring get cm -o=custom-columns=NAME:.metadata.name|grep grafana-dashboard-`
do
   oc get cm $i --namespace=openshift-monitoring --export=true -o yaml |oc apply --namespace=${GRAFANA_NAMESPACE} -f -
done

echo "-> Create ocp-prometheus service account and add viewer cluster role..."
oc -n ${GRAFANA_NAMESPACE} create sa ocp-prometheus
oc -n ${GRAFANA_NAMESPACE} adm policy add-cluster-role-to-user view -z ocp-prometheus
TOKEN=`oc -n ${GRAFANA_NAMESPACE} serviceaccounts get-token ocp-prometheus`

echo "-> Create OCP Prometheus datasource secret..."
cat << EOF > datasource-secret.yaml
apiVersion: 1
datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: "https://prometheus-k8s.openshift-monitoring.svc:9091"
    basicAuth: false
    withCredentials: false
    isDefault: true
    version: 1
    editable: true
    jsonData:
      tlsSkipVerify: true
      timeInterval: "5s"
      httpHeaderName1: "Authorization"
    secureJsonData:
      httpHeaderValue1: "Bearer $TOKEN"
EOF
oc -n ${GRAFANA_NAMESPACE} create secret generic datasource-secret --from-file=datasource-secret.yaml

echo "-> Deploy Grafana 7 helm chart..."
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update
helm install grafana7 -n ${GRAFANA_NAMESPACE} -f values.yml bitnami/grafana
sleep 20
echo "-> Create grafana7 route..."
oc -n ${GRAFANA_NAMESPACE} create route edge --service=grafana7
GRAFANA_HOST=`oc -n ${GRAFANA_NAMESPACE} get route grafana7 -o jsonpath={.spec.host}`

echo "GRFANA_URL: https://${GRAFANA_HOST}"
rm datasource-secret.yml
