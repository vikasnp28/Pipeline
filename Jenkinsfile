#!/usr/bin/env groovy

/* Import the below shared library stored in this GitHub repository:
        https://github.dxc.com/Platform-DXC/devops-jenkins-sharedlibs

    This library contains functions for parsing the CHANGELOG.md file
*/
@Library('pdxc-pipeline-lib@master')_

// this is required for global var notation @Field
import groovy.transform.Field

// Global variables for external Groovy scripts
@Field DSCScript
@Field GitScript
@Field GUIScript
@Field TerraformScript

@Field SetupProfileStage
@Field TriggerPipelineCheckStage
@Field CopyConfigFilesStage
@Field DefineVariablesStage
@Field DetokeniseStage
@Field DestroyAllStage
@Field ProvisionStorageAccountStage

@Field CQTerraformLintStage
@Field CQTerraformFormattingStage
@Field CQCheckEmailStage
@Field CQpssa

@Field CommonGlobalScript
@Field LoadScript

def loadScripts()
{
    // Once repositories are downloaded, import required scripts. Note each one must be
    // declared as a global variable above so they can be used throughout this file

    // This must be the first groovy script to load in case the vars are required in other Groovy scripts.
    CommonGlobalScript = load "${Globals.JenkinsRootFolder}/Groovy/CommonGlobal.groovy"
    // Helper Groovy functions
    DSCScript = load "${Globals.JenkinsRootFolder}/Groovy/DSC.groovy"
    GitScript = load "${Globals.JenkinsRootFolder}/Groovy/Git.groovy"
    GUIScript = load "${Globals.JenkinsRootFolder}/Groovy/GUI.groovy"
    TerraformScript = load "${Globals.JenkinsRootFolder}/Groovy/Terraform.groovy"

    // Stage related Groovy functions
    SetupProfileStage = load "${Globals.JenkinsRootFolder}/Groovy/stages/stage_SetupProfile.groovy"
    CopyConfigFilesStage = load "${Globals.JenkinsRootFolder}/Groovy/stages/stage_CopyConfigFiles.groovy"
    DetokeniseStage = load "${Globals.JenkinsRootFolder}/Groovy/stages/stage_Detokenise.groovy"
    DestroyAllStage = load "${Globals.JenkinsRootFolder}/Groovy/stages/stage_DestroyAll.groovy"
    ProvisionStorageAccountStage = load "${Globals.JenkinsRootFolder}/Groovy/stages/stage_ProvisionStorageAccount.groovy"
    GitHubReleaseStage = load "${Globals.JenkinsRootFolder}/Groovy/stages/stage_GitHubRelease.groovy"

    // Code Quality related Groovy functions
    CQTerraformLintStage = load "${Globals.JenkinsRootFolder}/Groovy/stages/stage_CQTerraformLint.groovy"
    CQTerraformFormattingStage = load "${Globals.JenkinsRootFolder}/Groovy/stages/stage_CQTerraformFormatting.groovy"
    CQCheckEmailStage = load "${Globals.JenkinsRootFolder}/Groovy/stages/stage_CQCheckEmail.groovy"
    CQpssa = load "${Globals.JenkinsRootFolder}/Groovy/stages/stage_CQpssa.groovy"

    // Local groovy scripts
    TriggerPipelineCheckStage = load "${Globals.RootPipelineFolder}/Groovy/stage_PipelineTriggerCheck.groovy"
    DefineVariablesStage = load "${Globals.RootPipelineFolder}/Groovy/stage_DefineVariables.groovy"
}

//###############################################################################################################################
//                  WALDO PIPELINE FOLDER STRUCTURE
// NOTE: The Waldo Framework repo contains a folder 'Pipeline' where all Pipeline related files are stored.
// Ensure all paths relating to pipeline files have 'Pipeline' after Workspace. This is so that the workspace passed in to all files
// from the Jenkins file already have the Pipeline subfolder path, to avoid having to modify paths in the rest of the files.
//###############################################################################################################################

// **************************************************************
// Globals
// **************************************************************
// Define global variables with defaults, some of which are set later
// using data retrieved from the (GUI) Configuration Database. The variable
// setting must run after the branch specific configuration file has
// been copied
// Use @Field notation to allow access/modification in functions
class Globals
{
    // The below variables are pipeline specific hence declared here
    static String ExecuteStepAzureAutomation = "no"
    static String ExecuteStepNetwork = "no"
    static String ExecuteStepDC = "no"
    static String ExecuteStepSQL = "no"
    static String ExecuteStepMaster          = "no"
    static String ExecuteStepSharePoint      = "no"

    static String ExecuteLoadDSCDC = "no"
    static String ExecuteLoadDSCSQL = "no"
    static String ExecuteLoadDSCMaster       = "no"
    static String ExecuteLoadDSCSharePoint   = "no"

    // Prefixes for each type of VM, assigned in Stage 1.3
    static String VMPrefixDC = ""
    static String VMPrefixSQL = ""
    static String VMPrefixMaster = ""
    static String VMPrefixSharePoint = ""

    // Number of Domain Controllers. Default for Waldo is two, one for Master Domain and one for Resource Domain.
    static Integer NumberOfDCs = 2

    // The below variables are not pipeline specific but here as they are regularly passed into Groovy functions

    // Global variable for Root folder where automation related code resides.
    // Typically the root of the GitHub repo
    static String RootPipelineFolder = ""
    static String RootFolder = ""

    // Global variables for folders where Jenkins related script files reside.
    static String JenkinsRootFolder = ""
    static String JenkinsPowerShellFolder = ""

    // this is the number of times to run a stage if it fails, this is, including the first run
    static Integer NumberOfRuns = 1

    // Name of Azure Automation Account, assigned in Stage 1.3
    static String AutomationAccountName = ""

    static String Domain = ""
    static String MasterDomain = ""
}

// **************************************************************

pipeline {
    agent {
        docker {
            image "docker.dxc.com/wm-docker/powershelldocker:1.0.0"
            registryUrl "https://docker.dxc.com"
            registryCredentialsId "PIPELINE_DOCKER_ACCOUNT"
        }
    }

    // Environment variables
    environment {

        TF_VAR_REGION               = "southcentralus"

        /*
            These secrets are:
                - stored within Jenkins credential store.
                - unqiue to a branch, hence the the appending of the branch_name
        */

        /*
        * Account details for Domain & VM admin
          Uses a Jenkins credential called "TF_VAR_ADMIN_ACCOUNT_<branch name>" and creates environment variables:
          "$TF_VAR_ADMIN_ACCOUNT" will contain string "USR:PSW"
          "$TF_VAR_ADMIN_ACCOUNT_USR" will contain string for Username
          "'$TF_VAR_ADMIN_ACCOUNT_PSW'" will contain string for Password
        */
        // Admin Account for Resource Domain - this is used for all other servers except Master Domain
        TF_VAR_ADMIN_ACCOUNT        = credentials("ADMIN_ACCOUNT_${env.BRANCH_NAME}")
        //The Admin Account is used for the Domain Safe Mode Password, Domain Join, and VM local admin.
        DomainJoinCreds             = credentials("ADMIN_ACCOUNT_${env.BRANCH_NAME}")
        ADConfigCreds               = credentials("ADMIN_ACCOUNT_${env.BRANCH_NAME}")

        // Admin Creds for Master Domain
        ADMasterConfigCreds          = credentials("MasterDomainAdminCreds_${env.BRANCH_NAME}")

        // Accounts specific to Waldo Framework
        SQLServiceCreds             = credentials("SQLServiceCreds_${env.BRANCH_NAME}")
        SQLAgentCreds               = credentials("SQLAgentCreds_${env.BRANCH_NAME}")
        SchedTaskCreds              = credentials("SchedTaskCreds_${env.BRANCH_NAME}")
        SPMgtCreds                  = credentials("SPMgtCreds_${env.BRANCH_NAME}")
        SPPassphraseCreds           = credentials("SPPassphraseCreds_${env.BRANCH_NAME}")
        SPAppCreds                  = credentials("SPAppCreds_${env.BRANCH_NAME}")
        SPWebCreds                  = credentials("SPWebCreds_${env.BRANCH_NAME}")
        // XUser creds are sourced from the same Jenkins credential, as the same user is created in both domains
        XUser1Creds                  = credentials("XUserCreds_${env.BRANCH_NAME}")
        XUser2Creds                  = credentials("XUserCreds_${env.BRANCH_NAME}")

        /*
            Web hooks to the predefined MS Teams channels
             - MSTeamsWebhookUrl is the channel to be used when the Offering execute the pipeline
             - MSTeamsWebhookUrl_DEV is the channel to be used when the Develop team execute the pipeline
             - Developer_Branches is a list of branch names used only by developers. Typically (but not always) the MSDN subscriptions.
        */
        MSTEAMS_WEBHOOKURL          = credentials("MSTeamsWebhookUrl")
        MSTEAMS_WEBHOOKURL_DEV      = credentials("MSTeamsWebhookUrl_DEV")
        DEVELOPER_BRANCHES          = credentials("Developer_Branches")

        // Get the Credential variable which indicates if a pipeline should run ("yes") or is disabled ("no")
        RUN_PIPELINE                = credentials("pipeline_enabled_${env.BRANCH_NAME}")

        /*
          Credentials to access the GitHub repo using the REST API
          Uses a Jenkins credential called "GIT_ACCOUNT" and creates environment variables:
          "$GIT_ACCOUNT" will contain string "USR:PSW"
          "$GIT_ACCOUNT_USR" will contain string for Username
          "$GIT_ACCOUNT_PSW" will contain string for Password
        */
        GIT_ACCOUNT = credentials("GIT_ACCOUNT")
    }

    // Keep Build history upto 10 days.
    // Keep last 10 build artifacts at a time.
    // Ads Build Time stamp to log file.
    // Disable concurrent builds.
    // Set generous timeout to give the pipeline enough time to complete
    options {
        buildDiscarder(logRotator(daysToKeepStr: '10', artifactNumToKeepStr: '10'))
        timestamps()
        disableConcurrentBuilds()
        timeout(time: 4, unit: 'HOURS')
        parallelsAlwaysFailFast()
    }
    // Stage names
    // Use X.0 for a main stage or a parallel separator stage
    // Use X.X for sub stages or parallel stages
    stages {
        stage('1.0 Configuration Stages') {
            stages {
                stage('1.1 Set up Workspace') {
                    steps {
                       script {
                            // Global variable for Root folder where automation related code resides.
                            // Typically the root of the GitHub repo
                            // Cant make these CommonGlobals as they are used to load them.

                             Globals.RootPipelineFolder = "${WORKSPACE}/Dev-Studio-Waldo-MWS-Pipeline"
                            Globals.JenkinsRootFolder = "${Globals.RootPipelineFolder}/Jenkins-Gallery"
                            Globals.JenkinsPowerShellFolder = "${Globals.JenkinsRootFolder}/Jenkins/PowerShell"
                            Globals.RootFolder = "${WORKSPACE}"

                            def RetryAttempt = 0

                            retry (Globals.NumberOfRuns) {
                                // retry this step if it fails the first time
                                if (RetryAttempt > 0) {
                                    echo 'The Set up Workspace stage retry count is: ' + RetryAttempt
                                }
                                RetryAttempt = RetryAttempt + 1

                                 // Download required common GitHub repositories
								sh "pwsh -File '/${Globals.RootFolder}/PullFromGitHub.ps1' -GitRepo 'workplace/Dev-Studio-Waldo-MWS-Pipeline' -ReleaseId 'beta1.8.0' -GitHubAPIKey '${env.GIT_ACCOUNT}' -TargetFolder '${Globals.RootFolder}' " 
                                sh "pwsh -File '/${Globals.RootPipelineFolder}/PowerShell/PullFromGitHub.ps1' -GitRepo 'workplace/Jenkins-Gallery' -ReleaseId '2.2.1' -GitHubAPIKey '${env.GIT_ACCOUNT}' -TargetFolder '${Globals.RootPipelineFolder}' "

                                loadScripts()
                                cg = CommonGlobalScript.Load()

                            }
                            SetupProfileStage.Execute()
                            TriggerPipelineCheckStage.Execute(cg)
                            CopyConfigFilesStage.Execute(cg)
                            DefineVariablesStage.Execute(cg)
                            DetokeniseStage.Execute(cg)
                            DestroyAllStage.Execute(cg)
                            ProvisionStorageAccountStage.Execute(cg)
                        }
                    }
                }
            }
        }
        stage('2.0 Code Quality Stages') {
            when {
                beforeAgent true
                not {
                    anyOf {
                        branch 'master';
                        branch 'integration'
                    }
                }
                expression {
                    return cg.ExecuteStepCodeQuality == 'yes';
                }
            }
            steps {
                script {
                    CQTerraformLintStage.Execute()
                    CQTerraformFormattingStage.Execute()
                    CQCheckEmailStage.Execute()
                    CQpssa.Execute(GUIScript)
                }
            }
        }
        stage('3.0 Provision Azure Automation') {
            when {
                expression {
                    return Globals.ExecuteStepAzureAutomation == 'yes';
                }
            }
            steps {
                script {
                    TerraformScript.createTerraformModule('azure-automation', Globals.NumberOfRuns, Globals.RootPipelineFolder)
                }
            }
        }
        stage('4.0 Provision Virtual Network') {
            when {
                expression {
                    return Globals.ExecuteStepNetwork == 'yes';
                }
            }
            steps {
                script {
                    TerraformScript.createTerraformModule('network', Globals.NumberOfRuns, Globals.RootPipelineFolder)
                }
            }
        }
        stage('5.0 Parallel Stages') {
            when {
                expression {
                    // If any of the parallel stages are flagged to run, run this parallel step
                    return (Globals.ExecuteLoadDSCDC == 'yes' || Globals.ExecuteLoadDSCMaster == 'yes' || Globals.ExecuteLoadDSCSQL == 'yes' || Globals.ExecuteLoadDSCSharePoint == 'yes' || Globals.ExecuteStepSharePoint == 'yes');
                }
            }
            parallel {
                stage('5.1 Configure Azure Automation') {
                    when {
                        expression {
                            // If any of the DSC Configuration steps are flagged to run, run this preparation step
                            return (Globals.ExecuteLoadDSCDC == 'yes' || Globals.ExecuteLoadDSCMaster == 'yes' || Globals.ExecuteLoadDSCSQL == 'yes' || Globals.ExecuteLoadDSCSharePoint == 'yes');
                        }
                    }
                    steps {
                        script {
                            def RetryAttempt = 0
                            retry(Globals.NumberOfRuns) {
                                // retry this step if it fails the first time
                                if (RetryAttempt > 0) {
                                    echo 'The Configure Azure Automation stage retry count is: ' + RetryAttempt
                                }
                                RetryAttempt = RetryAttempt + 1

                                // set pwsh session variables
                                sh "pwsh  -NoLogo -NonInteractive -ExecutionPolicy unrestricted"

                                // create Azure credentials for Resource domain - all credentials
                                sh "pwsh -File '/${Globals.JenkinsPowerShellFolder}/create-azure-credentials-with-pwds.ps1' -domain '${Globals.Domain}' -accountGroup 'Domain Accounts' "
                                // create Azure credentials for local accounts, no domain
                                sh "pwsh -File '/${Globals.JenkinsPowerShellFolder}/create-azure-credentials-with-pwds.ps1' -accountGroup 'Local Accounts' "
                                // create Azure credentials for the Master Domain - only for xuser2, this will overwrite the cred created by the first call
                                sh "pwsh -File '/${Globals.JenkinsPowerShellFolder}/create-azure-credentials-with-pwds.ps1' -domain '${Globals.MasterDomain}' -accountGroup 'Domain Accounts' -user 'XUser2Creds' "

                                // import custom DSC modules
                                echo 'Running Load/Compile DSC Modules'
                                sh "pwsh -File '/${Globals.JenkinsPowerShellFolder}/import-custom-dsc-modules.ps1' "
                                // import modules from PowerShell Gallery
                                sh "pwsh -File '/${Globals.JenkinsPowerShellFolder}/import-external-dsc-modules.ps1' "
                            }
                        }
                    }
                }
                stage('5.2 Provision VM (SharePoint)') {
                    when {
                        expression {
                            return Globals.ExecuteStepSharePoint == 'yes';
                        }
                    }
                    steps {
                        script {
                            TerraformScript.createTerraformModule('sharepoint-vm', Globals.NumberOfRuns, Globals.RootPipelineFolder)
                        }
                    }
                }
            }
        }
        stage('6.0 Parallel Stages') {
            when {
                expression {
                    // If any of the parallel stages are flagged to run, run this parallel step
                    return (Globals.ExecuteStepSQL == 'yes' || Globals.ExecuteLoadDSCSharePoint == 'yes');
                }
            }
            parallel {
                stage('6.1 Provision VM (SQL)') {
                    when {
                        expression {
                            return Globals.ExecuteStepSQL == 'yes';
                        }
                    }
                    steps {
                        script {
                            TerraformScript.createTerraformModule('sql-vm', Globals.NumberOfRuns, Globals.RootPipelineFolder)
                        }
                    }
                }
                stage('6.2 Install Software (SharePoint)') {
                    when {
                        expression {
                            return Globals.ExecuteLoadDSCSharePoint == 'yes';
                        }
                    }
                    steps {
                        script {
                            echo 'Running DSC Module Configuration for SharePoint'

                            DSCScript.configureSoftware(Globals.NumberOfRuns, "${Globals.VMPrefixSharePoint}001","${Globals.RootPipelineFolder}/DSC/SharePoint/SharePointConfig.ps1","${Globals.RootPipelineFolder}/DSC/SharePoint/SharePointConfigData.psd1", "SharePointConfig", "Install and Configure SharePoint Server for Waldo", Globals.RootPipelineFolder)
                        }
                    }
                }
            }
        }
        stage('7.0 Parallel Stages') {
            when {
                expression {
                    // If any of the parallel stages are flagged to run, run this parallel step
                    return (Globals.ExecuteStepDC == 'yes' || Globals.ExecuteLoadDSCSQL == 'yes');
                }
            }
            parallel {
               stage('7.1 Provision VM (DC)') {
                    when {
                        expression {
                            return Globals.ExecuteStepDC == 'yes';
                        }
                    }
                    steps {
                        script {
                            TerraformScript.createTerraformModule('dc-vm', Globals.NumberOfRuns, Globals.RootPipelineFolder)
                        }
                    }
                }
                stage('7.2 Install Software (SQL)') {
                    when {
                        expression {
                            return Globals.ExecuteLoadDSCSQL == 'yes';
                        }
                    }
                    steps {
                        script {
                            echo 'Running DSC Module Configuration for SQL'

                            DSCScript.configureSoftware(Globals.NumberOfRuns, "${Globals.VMPrefixSQL}001", "${Globals.RootPipelineFolder}/DSC/SQL/SQLInstall.ps1", "${Globals.RootPipelineFolder}/DSC/SQL/SQLInstallConfigData.psd1", "SQLInstall", "Install and Configure SQL Server for Waldo", Globals.RootPipelineFolder)
                        }
                    }
                }
            }
        }
        stage('8.0 Parallel Stages') {
            when {
                expression {
                    // If any of the parallel stages are flagged to run, run this parallel step
                    return (Globals.ExecuteStepMaster == 'yes' || Globals.ExecuteLoadDSCDC == 'yes');
                }
            }
            parallel {
                stage('8.1 Provision VM (Master)') {
                    when {
                        expression {
                            return Globals.ExecuteStepMaster == 'yes';
                        }
                    }
                    steps {
                        script {
                            TerraformScript.createTerraformModule('master-vm', Globals.NumberOfRuns, Globals.RootPipelineFolder)
                        }
                    }
                }
                stage('8.2 Install Software (DC1)') {
                    when {
                        expression {
                            return Globals.ExecuteLoadDSCDC == 'yes';
                        }
                    }
                    steps {
                        script {
                            echo 'Running DSC Module Configuration for DC1'

                            // first domain controller is for the Resource domain
                            DSCScript.configureSoftware(Globals.NumberOfRuns, "${Globals.VMPrefixDC}001", "${Globals.RootPipelineFolder}/DSC/ActiveDirectoryResource/ADResConfig.ps1", "${Globals.RootPipelineFolder}/DSC/ActiveDirectoryResource/ADResConfigData.psd1", "ADResConfig", "Install and Configure Domain Controller 1 for Waldo", Globals.RootPipelineFolder)
                        }
                    }
                }
                stage('8.3 Install Software (DC2)') {
                    when {
                        expression {
                            return (Globals.ExecuteLoadDSCDC == 'yes' && Globals.NumberOfDCs > 1) ;
                        }
                    }
                    steps {
                        script {
                            // Need to change local vm password for DC2 as both domain controllers are initially created with the same username/pwd, but
                            // DC2 is required to have a different password (can be same username). This needs to be done prior to loading the DSC config.
                            echo 'Setting local admin creds for DC2'

                            def RetryAttempt = 0
                            retry (Globals.NumberOfRuns) {
                                // retry this step if it fails the first time
                                if (RetryAttempt > 0) {
                                    echo 'Set local admin creds for DC2 retry count is: ' + RetryAttempt
                                }
                                RetryAttempt = RetryAttempt + 1

                                withCredentials([azureServicePrincipal(credentialsId: "azure_subscription_${env.BRANCH_NAME}")]) {
                                    // VMname is the VM where the local admin pwd will be set
                                    def VMname = "${Globals.VMPrefixDC}002"
                                    sh "pwsh -Command '/${Globals.JenkinsPowerShellFolder}/set-vm-admin-pwd.ps1' -JenkinsPowerShellFolder '${Globals.JenkinsPowerShellFolder}' -VMname '${VMname}' -adminUsername '${ADMasterConfigCreds_USR}' -adminPwd '${ADMasterConfigCreds_PSW}' "
                                }
                            }

                            echo 'Running DSC Module Configuration for DC2'

                            // second domain controller is for the Master Domain (separate concept to "Master Server" provisioned below)
                            DSCScript.configureSoftware(Globals.NumberOfRuns, "${Globals.VMPrefixDC}002", "${Globals.RootPipelineFolder}/DSC/ActiveDirectory/ADMasterConfig.ps1", "${Globals.RootPipelineFolder}/DSC/ActiveDirectory/ADMasterConfigData.psd1", "ADMasterConfig", "Install and Configure Domain Controller 2 for Waldo", Globals.RootPipelineFolder)
                      }
                    }
                }
            }
        }
        stage('9.0 Install Software (Master)') {
            when {
                expression {
                    return Globals.ExecuteLoadDSCMaster == 'yes';
                }
            }
            steps {
                script {
                    echo 'Running DSC Module Configuration for Master'

                    DSCScript.configureSoftware(Globals.NumberOfRuns, "${Globals.VMPrefixMaster}001", "${Globals.RootPipelineFolder}/DSC/Master/MasterConfig.ps1", "${Globals.RootPipelineFolder}/DSC/Master/MasterConfigData.psd1", "MasterConfig", "Install and Configure Master Server for Waldo", Globals.RootPipelineFolder)
                }
            }
        }
        stage('10.0 Wait for DSC (DC)') {
            when {
                expression {
                    return (Globals.ExecuteLoadDSCDC == 'yes' && cg.ExecuteMSTeamsNotificationDSC == 'yes');
                }
            }
            steps {
                script {
                    def RetryAttempt = 0
                    retry (Globals.NumberOfRuns) {
                        // retry this step if it fails the first time
                        if (RetryAttempt > 0) {
                            echo 'The Wait for DSC (DC1) stage retry count is: ' + RetryAttempt
                        }
                        RetryAttempt = RetryAttempt + 1
                        withCredentials([azureServicePrincipal(credentialsId: "azure_subscription_${env.BRANCH_NAME}")]) {
                            sh "pwsh -Command '/${Globals.JenkinsPowerShellFolder}/get-dsc-configuration.ps1' -VMname '${Globals.VMPrefixDC}001' -developerBranches ${env.DEVELOPER_BRANCHES} -webhookDev ${env.MSTEAMS_WEBHOOKURL_DEV} -webhookOffering ${env.MSTEAMS_WEBHOOKURL} -tenantID $AZURE_TENANT_ID -SubscriptionID $AZURE_SUBSCRIPTION_ID  -ConfigName 'Active-Directory1' -buildNumber ${currentBuild.number.toString()} -fullDisplayName '${cg.FullDisplayName}' -retryAttempt ${RetryAttempt} "
                        }
                    }
                    if  (Globals.NumberOfDCs > 1) {
                        RetryAttempt = 0
                        retry (Globals.NumberOfRuns) {
                            // retry this step if it fails the first time
                            if (RetryAttempt > 0) {
                                echo 'The Wait for DSC (DC2) stage retry count is: ' + RetryAttempt
                            }
                            RetryAttempt = RetryAttempt + 1

                            withCredentials([azureServicePrincipal(credentialsId: "azure_subscription_${env.BRANCH_NAME}")]) {
                                sh "pwsh -Command '/${Globals.JenkinsPowerShellFolder}/get-dsc-configuration.ps1' -VMname '${Globals.VMPrefixDC}002' -developerBranches ${env.DEVELOPER_BRANCHES} -webhookDev ${env.MSTEAMS_WEBHOOKURL_DEV} -webhookOffering ${env.MSTEAMS_WEBHOOKURL} -tenantID $AZURE_TENANT_ID -SubscriptionID $AZURE_SUBSCRIPTION_ID  -ConfigName 'Active-Directory2' -buildNumber ${currentBuild.number.toString()} -fullDisplayName '${FullDisplayName}' -retryAttempt ${RetryAttempt} "
                            }
                        }
                    }
                }
            }
        }
        stage('11.0 Wait for DSC (Master)') {
            when {
                expression {
                    return (Globals.ExecuteLoadDSCMaster == 'yes' && cg.ExecuteMSTeamsNotificationDSC == 'yes');
                }
            }
            steps {
                script {
                    def RetryAttempt = 0
                    retry (Globals.NumberOfRuns) {
                        // retry this step if it fails the first time
                        if (RetryAttempt > 0) {
                            echo 'The Wait for DSC (Master) stage retry count is: ' + RetryAttempt
                        }
                        RetryAttempt = RetryAttempt + 1

                        withCredentials([azureServicePrincipal(credentialsId: "azure_subscription_${env.BRANCH_NAME}")]) {
                            sh "pwsh -Command '/${Globals.JenkinsPowerShellFolder}/get-dsc-configuration.ps1' -VMname '${Globals.VMPrefixMaster}001' -developerBranches ${env.DEVELOPER_BRANCHES} -webhookDev ${env.MSTEAMS_WEBHOOKURL_DEV} -webhookOffering ${env.MSTEAMS_WEBHOOKURL} -tenantID $AZURE_TENANT_ID -SubscriptionID $AZURE_SUBSCRIPTION_ID  -ConfigName 'Master-Server' -buildNumber ${currentBuild.number.toString()} -fullDisplayName '${cg.FullDisplayName}' -retryAttempt ${RetryAttempt} "
                        }
                    }
                }
            }
        }
        stage('12.0 Wait for DSC (SQL)') {
            when {
                expression {
                    return (Globals.ExecuteLoadDSCSQL == 'yes' && cg.ExecuteMSTeamsNotificationDSC == 'yes');
                }
            }
            steps {
                script {
                    def RetryAttempt = 0
                    retry (Globals.NumberOfRuns) {
                        // retry this step if it fails the first time
                        if (RetryAttempt > 0) {
                            echo 'The Wait for DSC (SQL) stage retry count is: ' + RetryAttempt
                        }
                        RetryAttempt = RetryAttempt + 1

                        withCredentials([azureServicePrincipal(credentialsId: "azure_subscription_${env.BRANCH_NAME}")]) {
                            sh "pwsh -Command '/${Globals.JenkinsPowerShellFolder}/get-dsc-configuration.ps1' -VMname '${Globals.VMPrefixSQL}001' -developerBranches ${env.DEVELOPER_BRANCHES} -webhookDev ${env.MSTEAMS_WEBHOOKURL_DEV} -webhookOffering ${env.MSTEAMS_WEBHOOKURL} -tenantID $AZURE_TENANT_ID -SubscriptionID $AZURE_SUBSCRIPTION_ID  -ConfigName 'SQL-Server' -buildNumber ${currentBuild.number.toString()} -fullDisplayName '${cg.FullDisplayName}' -retryAttempt ${RetryAttempt} "
                        }
                    }
                }
            }
        }
        stage('13.0 Wait for DSC (SharePoint)') {
            when {
                expression {
                    return (Globals.ExecuteLoadDSCSharePoint == 'yes' && cg.ExecuteMSTeamsNotificationDSC == 'yes');
                }
            }
            steps {
                script {
                    def RetryAttempt = 0
                    retry (Globals.NumberOfRuns) {
                        // retry this step if it fails the first time
                        if (RetryAttempt > 0) {
                            echo 'The Wait for DSC (SharePoint) stage retry count is: ' + RetryAttempt
                        }
                        RetryAttempt = RetryAttempt + 1

                        withCredentials([azureServicePrincipal(credentialsId: "azure_subscription_${env.BRANCH_NAME}")]) {
                            sh "pwsh -Command '/${Globals.JenkinsPowerShellFolder}/get-dsc-configuration.ps1' -VMname '${Globals.VMPrefixSharePoint}001' -developerBranches ${env.DEVELOPER_BRANCHES} -webhookDev ${env.MSTEAMS_WEBHOOKURL_DEV} -webhookOffering ${env.MSTEAMS_WEBHOOKURL} -tenantID $AZURE_TENANT_ID -SubscriptionID $AZURE_SUBSCRIPTION_ID  -ConfigName 'SharePoint-Server' -buildNumber ${currentBuild.number.toString()} -fullDisplayName '${cg.FullDisplayName}' -retryAttempt ${RetryAttempt} "
                        }
                    }
                }
            }
        }
        stage('14.0 Run Pester Tests') {
            when {
                expression {
                    return (cg.ExecutePesterTests == 'yes');
                }
            }
            steps {
                script {
                    def RetryAttempt = 0
                    retry (Globals.NumberOfRuns) {
                        // retry this step if it fails the first time
                        if (RetryAttempt > 0) {
                            echo 'The Run Pester Tests stage retry count is: ' + RetryAttempt
                        }
                        RetryAttempt = RetryAttempt + 1

                        // for consecutive runs, ensure that this file is deleted before running Pester Tests
                        sh "rm -f '/${Globals.RootPipelineFolder}/ALL_PESTER_TESTS_PASSED.txt' "

                        withCredentials([azureServicePrincipal(credentialsId: "azure_subscription_${env.BRANCH_NAME}")]) {
                            // VMname is the VM where the Pester Tests will be run, if tihs is changed then make the same change in the SharePoint config psd1,
                            // as it stores the name of the VM where Pester Tests are run so that it can add the computer name to the list of SharePoint site owners
                            // to allow access when running the SharePoint Pester Test.
                            def VMname = "${Globals.VMPrefixDC}001"
                            // Custom parameters are required to keep the scripts generic, use format <key>=<value> where '_' is the key/value delimiter
                            def CustomParams = "resourceDomainAdminUsername=${ADConfigCreds_USR}" + '_' + "resourceDomainAdminPwd=${ADConfigCreds_PSW}" + '_' +
                                               "masterDomainAdminUsername=${ADMasterConfigCreds_USR}" + '_' + "masterDomainAdminPwd=${ADMasterConfigCreds_PSW}"
                            sh "pwsh -Command '/${Globals.JenkinsPowerShellFolder}/run-pester-tests.ps1' -repoRootPath '${WORKSPACE}' -JenkinsPowerShellFolder '${Globals.JenkinsPowerShellFolder}' -VMname '${VMname}' -currentBranch ${env.BRANCH_NAME} -developerBranches ${env.DEVELOPER_BRANCHES} -webhookDev ${env.MSTEAMS_WEBHOOKURL_DEV} -webhookOffering ${env.MSTEAMS_WEBHOOKURL} -SubscriptionID $AZURE_SUBSCRIPTION_ID -buildNumber ${currentBuild.number.toString()} -customParams '${CustomParams}' "
                        }
                    }

                    // Pester Test Failures vs Command Failures - this is specific to an offering to decide if the pipeline should fail if a Pester Test fails.
                    // If all Pester Tests pass, then a file will be created at the Globals.RootPipelineFolder level from the run-pester-tests script.
                    // If at least one Pester Test returns a result where 'Fails' is nonzero, then this is a Pester Test failure.
                    // This check is handled outside of the retry loop, as we do not want a Pester Test failure to trigger a retry.
                    // All other failures, such as an azure command failure, will still trigger the retry loop.
                    if (fileExists("/${Globals.RootPipelineFolder}/ALL_PESTER_TESTS_PASSED.txt") == false)
                    {
                        echo 'Pester Tests were NOT all successful, exiting Pipeline'
                        Exit 1
                    }
                }
            }
        }
    }
    post {
        always { // Run the steps in the post section regardless of the completion status of the Pipeline's or stage's run.
            echo 'One way or another, I have finished'
            /*
                Clean up workspace.
                This should be commented until Backend storage is configured
                 as it will 'break' Terraform by deleting the tfstate file.
                Only use if the tfstate file falls out of sync with actual infrastrucutre within Azure.
            */
            //deleteDir()

            /*
            * Depending on where the failure occurs some of the pre-reqs script may not have been executed yet,
            * so executing them (potentially for a 2nd time) here.
            * These additional steps cause the post build actions to run for up to a minute
            */
            // load Powershell modules
            sh "pwsh -File '/${Globals.JenkinsPowerShellFolder}/load-modules.ps1' "
            withCredentials([azureServicePrincipal(credentialsId: "azure_subscription_${env.BRANCH_NAME}")]) {
                // Connect to Azure subscriptions
                sh "pwsh -File '/${Globals.JenkinsPowerShellFolder}/connect-az.ps1' -SubscriptionID $AZURE_SUBSCRIPTION_ID -TenantId $AZURE_TENANT_ID -ApplicationID $AZURE_CLIENT_ID -ServicePrincipalSecret $AZURE_CLIENT_SECRET "
            }
            // Check if the lease on the files within Azure storage still exist. If so break the lease.
            // This typically happens when the pipeline fails.
            sh "pwsh -File '/${Globals.JenkinsPowerShellFolder}/break-storage-lease.ps1' "

            script {
                // Reset the duration
                cg.Duration = currentBuild.durationString.toString().replaceAll(' ', '-')
            }
        }
        success { // Only run the steps in post if the current Pipeline's or stage's run has a "success" status
            echo 'I succeeeded!'
            script{
                if(cg.ExecuteMSTeamsNotificationCompleted == 'yes') {
                    sh "pwsh -Command '/${Globals.JenkinsPowerShellFolder}/msteams-notifications-jenkins-completed.ps1' -status 'SUCCESS' -BlueOceanUrl ${cg.BlueOceanUrl} -currentBranch ${env.BRANCH_NAME} -developerBranches ${env.DEVELOPER_BRANCHES} -webhookDev ${env.MSTEAMS_WEBHOOKURL_DEV} -webhookOffering ${env.MSTEAMS_WEBHOOKURL} -durationString '${cg.Duration}' -buildNumber ${currentBuild.number.toString()} -fullDisplayName '${cg.FullDisplayName}' -notificationMessage '${cg.NotificationMessage}' "
                }
           }
        }
        failure { // Only run the steps in post if the current Pipeline's or stage's run has a "failed" status
            echo 'I failed :('
            script{
                if(cg.ExecuteMSTeamsNotificationCompleted == 'yes') {
                    sh "pwsh -Command '/${Globals.JenkinsPowerShellFolder}/msteams-notifications-jenkins-completed.ps1' -status 'FAILED' -BlueOceanUrl ${cg.BlueOceanUrl} -currentBranch ${env.BRANCH_NAME} -developerBranches ${env.DEVELOPER_BRANCHES} -webhookDev ${env.MSTEAMS_WEBHOOKURL_DEV} -webhookOffering ${env.MSTEAMS_WEBHOOKURL} -durationString '${cg.Duration}' -buildNumber ${currentBuild.number.toString()} -fullDisplayName '${cg.FullDisplayName}' -notificationMessage '${cg.NotificationMessage}' "
                }
            }
        }
        aborted { // Pipeline is aborted manually, or by trigger conditions
            echo 'I was aborted :('
            script{
                if(cg.ExecuteMSTeamsNotificationCompleted == 'yes') {
                    sh "pwsh -Command '/${Globals.JenkinsPowerShellFolder}/msteams-notifications-jenkins-completed.ps1' -status ${cg.AbortStatus} -BlueOceanUrl ${cg.BlueOceanUrl} -currentBranch ${env.BRANCH_NAME} -developerBranches ${env.DEVELOPER_BRANCHES} -webhookDev ${env.MSTEAMS_WEBHOOKURL_DEV} -webhookOffering ${env.MSTEAMS_WEBHOOKURL} -durationString '${cg.Duration}' -buildNumber ${currentBuild.number.toString()} -fullDisplayName '${cg.FullDisplayName}' -notificationMessage '${cg.NotificationMessage}' "
                }
            }
        }
    }
}
