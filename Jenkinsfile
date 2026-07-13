@Library('jenkins.shared.library') _

pipeline {
 agent {
   label 'ubuntu_docker_label'
 }
 environment {
   HELM_IMAGE = "infoblox/helm:3"
   VERSION = sh(script: "git describe --always --long --tags | sed s/^prometheus-kafka-adapter-//", returnStdout: true).trim()
   TAG = "${env.VERSION}-j${env.BUILD_NUMBER}"
 }
 stages {
   stage("Build Image") {
     steps {
       sh 'docker build . -t prometheus.kafka.adapter:$TAG'
     }
   }
   stage("Package Chart") {
     steps {
       dir("helm") {
         withAWS(credentials: "CICD_HELM", region: "us-east-1") {
           sh '''
             docker run --rm \
                 -e AWS_REGION \
                 -e AWS_ACCESS_KEY_ID \
                 -e AWS_SECRET_ACCESS_KEY \
                 -v $(pwd):/pkg \
                 $HELM_IMAGE package /pkg/prometheus-kafka-adapter --app-version $TAG --version $TAG -d /pkg
           '''
         }
       }
     }
   }
   stage("Push Chart") {
     steps {
       withAWS(credentials: "CICD_HELM", region: "      us-east-1") {
         sh '''
           chart_file=prometheus-kafka-adapter-$TAG.tgz
           docker run --rm \
               -e AWS_REGION \
               -e AWS_ACCESS_KEY_ID \
               -e AWS_SECRET_ACCESS_KEY \
               -v $(pwd)/helm:/pkg \
               $HELM_IMAGE s3 push /pkg/$chart_file infobloxcto
           echo "repo=infobloxcto" > build.properties
           echo "chart=$chart_file" >> build.properties
           echo "messageFormat=s3-artifact" >> build.properties
           echo "customFormat=true" >> build.properties
         '''
       }
       archiveArtifacts artifacts: 'build.properties'
       archiveArtifacts artifacts: 'helm/*.tgz'
     }
   }
 }
 post {
    success {
        finalizeBuild(
            sh(
                script: "echo prometheus.kafka.adapter:$TAG",
                returnStdout: true
            )
        )
    }
 }
}
