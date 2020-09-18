#!/bin/sh

# Optional ENV variables:
# * ZK_CHROOT: the zookeeper chroot that's used by Kafka (without / prefix), e.g. "kafka"
# * LOG_RETENTION_HOURS: the minimum age of a log file in hours to be eligible for deletion (default is 168, for 1 week)
# * LOG_RETENTION_BYTES: configure the size at which segments are pruned from the log, (default is 1073741824, for 1GB)
# * NUM_PARTITIONS: configure the default number of log partitions per topic
# * ADVERTISED_LISTENERS: the listeners advertised to the outside world with associated listener name
# * LISTENERS: the listeners being created by the broker with their associated name
# * SECURITY_PROTOCOL_MAP: mapping from the listener names to security protocol
# * INTER_BROKER: the listener name the internal connections will use

# Allow specification of log retention policies

# Configure kerberos for kafka
echo "Make sure new config items are put at end of config file even if no newline is present as final character in the config"
echo >> $KAFKA_HOME/config/server.properties    

if [ ! -z "$ENABLE_KERBEROS" ]; then
    echo "set SASL mechanism"
    if grep -r -q "^#\?sasl.enabled.mechanisms" $KAFKA_HOME/config/server.properties; then
        sed -r -i "s/#?(sasl.enabled.mechanisms)=(.*)/\1=GSSAPI/g" $KAFKA_HOME/config/server.properties
    else
        echo "sasl.enabled.mechanisms=GSSAPI" >> $KAFKA_HOME/config/server.properties
    fi

    echo "set Kerberos service name for kafka"
    if grep -r -q "^#\?sasl.kerberos.service.name" $KAFKA_HOME/config/server.properties; then
        sed -r -i "s/#?(sasl.kerberos.service.name)=(.*)/\1=kafka/g" $KAFKA_HOME/config/server.properties
    else
        echo "sasl.kerberos.service.name=kafka" >> $KAFKA_HOME/config/server.properties
    fi

    echo "create jaas config based on template"
    sed "s/HOSTNAME/$(hostname -f)/g" $KAFKA_HOME/config/kafka.jaas.tmpl > $KAFKA_HOME/config/kafka.jaas

    export KAFKA_OPTS="-Djava.security.auth.login.config=${KAFKA_HOME}/config/kafka.jaas -Djava.security.krb5.conf=/etc/krb5.conf -Dsun.security.krb5.debug=true"
fi

if [ ! -z "$LOG_RETENTION_HOURS" ]; then
    echo "log retention hours: $LOG_RETENTION_HOURS"
    sed -r -i "s/#?(log.retention.hours)=(.*)/\1=$LOG_RETENTION_HOURS/g" $KAFKA_HOME/config/server.properties
fi
if [ ! -z "$LOG_RETENTION_BYTES" ]; then
    echo "log retention bytes: $LOG_RETENTION_BYTES"
    sed -r -i "s/#?(log.retention.bytes)=(.*)/\1=$LOG_RETENTION_BYTES/g" $KAFKA_HOME/config/server.properties
fi

# Configure the default number of log partitions per topic
if [ ! -z "$NUM_PARTITIONS" ]; then
    echo "default number of partition: $NUM_PARTITIONS"
    sed -r -i "s/#?(num.partitions)=(.*)/\1=$NUM_PARTITIONS/g" $KAFKA_HOME/config/server.properties
fi

# Enable/disable auto creation of topics
if [ ! -z "$AUTO_CREATE_TOPICS" ]; then
    echo "auto.create.topics.enable: $AUTO_CREATE_TOPICS"
    if grep -r -q "^#\?auto.create.topics.enable" $KAFKA_HOME/config/server.properties; then
        sed -r -i "s/#?(auto.create.topics.enable)=(.*)/\1=$AUTO_CREATE_TOPICS/g" $KAFKA_HOME/config/server.properties
    else
        echo "auto.create.topics.enable=$AUTO_CREATE_TOPICS" >> $KAFKA_HOME/config/server.properties
    fi
fi

if [ ! -z "$ADVERTISED_LISTENERS" ]; then
    echo "advertised.listeners: ${ADVERTISED_LISTENERS}"
    if grep -r -q "^#\?advertised.listeners=" $KAFKA_HOME/config/server.properties; then
        # use | as a delimiter to make sure // does not confuse sed
        sed -r -i "s|^#?(advertised.listeners)=(.*)|\1=${ADVERTISED_LISTENERS}|g" $KAFKA_HOME/config/server.properties
    else
        echo "advertised.listeners=${ADVERTISED_LISTENERS}" >> $KAFKA_HOME/config/server.properties
    fi
fi

if [ ! -z "$LISTENERS" ]; then
    echo "listeners: ${LISTENERS}"
    if grep -r -q "^#\?listeners=" $KAFKA_HOME/config/server.properties; then
        # use | as a delimiter to make sure // does not confuse sed
        sed -r -i "s|^#?(listeners)=(.*)|\1=${LISTENERS}|g" $KAFKA_HOME/config/server.properties
    else
        echo "listeners=${LISTENERS}" >> $KAFKA_HOME/config/server.properties
    fi
fi

if [ ! -z "$SECURITY_PROTOCOL_MAP" ]; then
    echo "listener.security.protocol.map: ${SECURITY_PROTOCOL_MAP}"
    if grep -r -q "^#\?listener.security.protocol.map=" $KAFKA_HOME/config/server.properties; then
        sed -r -i "s/^#?(listener.security.protocol.map)=(.*)/\1=${SECURITY_PROTOCOL_MAP}/g" $KAFKA_HOME/config/server.properties
    else
        echo "listener.security.protocol.map=${SECURITY_PROTOCOL_MAP}" >> $KAFKA_HOME/config/server.properties
    fi
fi

if [ ! -z "$INTER_BROKER" ]; then
    echo "inter.broker.listener_name: ${INTER_BROKER}"
    if grep -r -q "^#\?inter.broker.listener.name=" $KAFKA_HOME/config/server.properties; then
        sed -r -i "s/^#?(inter.broker.listener.name)=(.*)/\1=${INTER_BROKER}/g" $KAFKA_HOME/config/server.properties
    else
        echo "inter.broker.listener.name=${INTER_BROKER}" >> $KAFKA_HOME/config/server.properties
    fi
fi

if echo "$SECURITY_PROTOCOL_MAP" | grep -q ":SSL"; then
    if [ ! -f /var/private/ssl/server.keystore.jks ]; then
        if [ -z "$SSL_PASSWORD" ]; then
            SSL_PASSWORD=`date +%s | sha256sum | base64 | head -c 32`
        fi
        if [ ! -z "$SSL_CERT" ]; then
            mkdir -p /var/private/ssl/server/
            echo "${SSL_KEY}" >> /var/private/ssl/server/ssl.key
            echo "${SSL_CERT}" >> /var/private/ssl/server/cert.pem
            openssl pkcs12 -export -in /var/private/ssl/server/cert.pem -inkey /var/private/ssl/server/ssl.key -name localhost -password pass:${SSL_PASSWORD} -out /var/private/ssl/server/pkcs12.p12
            ${JAVA_HOME}/bin/keytool -importkeystore -deststorepass ${SSL_PASSWORD} -destkeypass ${SSL_PASSWORD} -destkeystore /var/private/ssl/server.keystore.jks -srckeystore /var/private/ssl/server/pkcs12.p12 -srcstoretype PKCS12 -srcstorepass ${SSL_PASSWORD} -alias localhost
        else  
            ${JAVA_HOME}/bin/keytool -genkey -noprompt -alias localhost -dname "${SSL_DN}" -keystore /var/private/ssl/server.keystore.jks --storepass ${SSL_PASSWORD} --keypass ${SSL_PASSWORD}
        fi
        if grep -r -q "^#\?ssl.keystore.location=" $KAFKA_HOME/config/server.properties; then
            # use | as a delimiter to make sure // does not confuse sed
            sed -r -i "s|^#?(ssl.keystore.location)=(.*)|\1=/var/private/ssl/server.keystore.jks|g" $KAFKA_HOME/config/server.properties
        else
            echo "ssl.keystore.location=/var/private/ssl/server.keystore.jks" >> $KAFKA_HOME/config/server.properties
        fi
        if grep -r -q "^#\?ssl.keystore.password=" $KAFKA_HOME/config/server.properties; then
            # use | as a delimiter to make sure // does not confuse sed
            sed -r -i "s|^#?(ssl.keystore.password)=(.*)|\1=${SSL_PASSWORD}|g" $KAFKA_HOME/config/server.properties
        else
           echo "ssl.keystore.password=${SSL_PASSWORD}" >> $KAFKA_HOME/config/server.properties
        fi
        if grep -r -q "^#\?ssl.key.password=" $KAFKA_HOME/config/server.properties; then
            # use | as a delimiter to make sure // does not confuse sed
            sed -r -i "s|^#?(ssl.key.password)=(.*)|\1=${SSL_PASSWORD}|g" $KAFKA_HOME/config/server.properties
        else
            echo "ssl.key.password=${SSL_PASSWORD}" >> $KAFKA_HOME/config/server.properties
        fi
    fi
fi

if [ ! -z "$HOSTNAME" ]; then
    echo "zookeeper connect string to $HOSTNAME"
    if grep -r -q "^#\?zookeeper.connect=" $KAFKA_HOME/config/server.properties; then
        sed -r -i "s/^#?(zookeeper.connect)=(.*)/\1=${HOSTNAME}:2181/g" $KAFKA_HOME/config/server.properties
    else
        echo "zookeeper.connect=${HOSTNAME}:2181" >> $KAFKA_HOME/config/server.properties
    fi
fi

export EXTRA_ARGS="-name kafkaServer" # no -loggc to minimize logging
$KAFKA_HOME/bin/kafka-server-start.sh $KAFKA_HOME/config/server.properties
