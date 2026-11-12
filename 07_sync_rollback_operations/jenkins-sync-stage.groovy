# ======================================================================
# FILE   : jenkins-sync-stage.groovy
# PURPOSE: Jenkins stage that syncs and waits for health.
# APPLY  : put in your Jenkinsfile
# ======================================================================
// Approach: let the CI pipeline trigger and wait for the deploy (CLI + token, no UI).
// Token: argocd account generate-token --account ci-user   (or a project role token, see folder 12)
stage('Deploy via Argo CD') {
  environment {
    ARGOCD_SERVER     = 'argocd.example.com'
    ARGOCD_AUTH_TOKEN = credentials('argocd-ci-token')   // Jenkins credential
  }
  steps {
    sh '''
      argocd app set  fcoos-insights -p image.tag=${BUILD_NUMBER} --grpc-web   # only for Helm param override mode
      argocd app sync fcoos-insights --grpc-web
      argocd app wait fcoos-insights --health --timeout 300 --grpc-web
    '''
  }
}
// With Image Updater you usually do NOT need this stage: Jenkins only pushes the image.
