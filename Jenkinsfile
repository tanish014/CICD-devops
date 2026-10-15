// Declarative pipeline for the Cloud-Native DevOps platform.
// Runs on the Jenkins server (EC2 #1). EDIT the two placeholders in `environment` before first use.
pipeline {
  agent any

  options {
    timestamps()
    disableConcurrentBuilds()
    buildDiscarder(logRotator(numToKeepStr: '20'))
  }

  triggers { githubPush() }   // fired by the GitHub webhook

  environment {
    DOCKERHUB_USER = 'tanish014'   // <-- edit
    APP_HOST       = '10.20.1.120'          // <-- edit: `terraform output app_private_ip`
    IMAGE_NAME     = "${DOCKERHUB_USER}/devops-app"
  }

  stages {
    stage('Checkout') {
      steps {
        checkout scm
        script {
          env.GIT_SHORT = sh(returnStdout: true, script: 'git rev-parse --short HEAD').trim()
          env.IMAGE_TAG = "${env.BUILD_NUMBER}-${env.GIT_SHORT}"
        }
      }
    }

    // Node.js runs inside a throwaway container, so the Jenkins host only needs Docker.
    stage('Install Dependencies') {
      steps {
        sh '''
          docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp \
            -v "$WORKSPACE/app":/app -w /app node:20-alpine npm ci
        '''
      }
    }

    stage('Automated Tests') {
      steps {
        sh '''
          docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp \
            -v "$WORKSPACE/app":/app -w /app node:20-alpine npm test
        '''
      }
    }

    stage('Docker Build') {
      steps {
        sh '''
          docker build \
            --build-arg APP_VERSION=1.0.0 \
            --build-arg GIT_COMMIT="$GIT_SHORT" \
            --build-arg BUILD_NUMBER="$BUILD_NUMBER" \
            --build-arg IMAGE_TAG="$IMAGE_TAG" \
            -t "$IMAGE_NAME:$IMAGE_TAG" -t "$IMAGE_NAME:latest" app/
        '''
      }
    }

    stage('Docker Hub Push') {
      steps {
        withCredentials([usernamePassword(credentialsId: 'dockerhub',
                                          usernameVariable: 'DH_USER', passwordVariable: 'DH_PASS')]) {
          sh '''
            echo "$DH_PASS" | docker login -u "$DH_USER" --password-stdin
            docker push "$IMAGE_NAME:$IMAGE_TAG"
            docker push "$IMAGE_NAME:latest"
          '''
        }
      }
    }

    stage('Deploy to k3s') {
      steps {
        sshagent(credentials: ['app-server-ssh']) {
          sh '''
            SSH_OPTS="-o StrictHostKeyChecking=accept-new"
            ssh $SSH_OPTS ubuntu@"$APP_HOST" "rm -rf ~/deploy && mkdir -p ~/deploy"
            scp $SSH_OPTS -r k8s scripts/deploy.sh ubuntu@"$APP_HOST":~/deploy/
            ssh $SSH_OPTS ubuntu@"$APP_HOST" "bash ~/deploy/deploy.sh $IMAGE_NAME:$IMAGE_TAG"
          '''
        }
      }
    }
  }

  post {
    always  { sh 'docker logout || true; docker image prune -f || true' }
    success { echo "Deployed ${env.IMAGE_NAME}:${env.IMAGE_TAG}" }
    failure { echo 'Pipeline failed - check the stage logs above.' }
  }
}
