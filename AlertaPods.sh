#!/bin/bash

# Variables
NAMESPACE="default"  # Cambia esto si usas otro namespace
SNS_TOPIC_ARN="arn:aws:sns:us-east-1:125146271723:AlertasEstadoPodsError"  # Reemplaza con tu ARN de SNS
DEPLOYMENT_FILE="./k8s/deployment.yaml"
S3_BUCKET="bdb-archivos"


# Obtener el estado de los pods
pods=$(kubectl get pods -n $NAMESPACE --no-headers)

# Filtrar pods que no están en estado "Running"
non_running_pods=""
while read -r pod; do
    pod_name=$(echo $pod | awk '{print $1}')
    pod_status=$(echo $pod | awk '{print $3}')
    
    if [ "$pod_status" != "Running" ]; then
        non_running_pods="$non_running_pods$pod_name($pod_status)"
                 # Obtener los logs del pod
        log_file="/tmp/${pod_name}_logs.txt"
        kubectl logs $pod_name -n $NAMESPACE > $log_file 2>&1
        
        # Subir los logs a S3
        aws s3 cp $log_file s3://$S3_BUCKET/${pod_name}_logs.txt
        
        # Eliminar el archivo temporal después de subirlo
        #rm -f $log_file
    fi
done <<EOF
$pods
EOF

# Si hay pods que no están en estado "Running", enviar notificación y aplicar deployment.yaml
if [ -n "$non_running_pods" ]; then
    echo "Pods no en estado Running encontrados:"
    printf "$non_runing_pods"

    # Construir el mensaje de notificación
    message="Los siguientes pods no están en estado Running:\n$non_running_pods"
    printf "$message"
    # Enviar notificación a SNS
    aws sns publish --topic-arn $SNS_TOPIC_ARN --message "$message" --subject "Alerta: Pods no en estado Running"

    # Aplicar el archivo deployment.yaml
    echo "Aplicando el archivo deployment.yaml..."
    kubectl apply -f $DEPLOYMENT_FILE -n $NAMESPACE

else
    echo "Todos los pods están en estado Running."
fi
