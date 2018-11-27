import jenkins.model.*
import hudson.model.AbstractItem
import com.cloudbees.jenkins.plugins.sshcredentials.*
import com.cloudbees.jenkins.plugins.sshcredentials.impl.*
import com.cloudbees.plugins.credentials.*
import com.cloudbees.plugins.credentials.domains.*
import com.cloudbees.plugins.credentials.impl.*
import com.cloudbees.plugins.credentials.common.*
import javax.xml.transform.stream.*

private credentials_for_username(String username) {
   def username_matcher = CredentialsMatchers.withUsername(username)
   def available_credentials =
     CredentialsProvider.lookupCredentials(
       StandardUsernameCredentials.class,
       Jenkins.getInstance(),
       hudson.security.ACL.SYSTEM,
       new SchemeRequirement("ssh")
     )

   return CredentialsMatchers.firstOrNull(
     available_credentials,
     username_matcher
   )
 }

def jobName = "SeedJob"

def git_url = System.getenv('SEEDJOB_GIT')
def git_username = System.getenv("GIT_USERNAME")
def git_ssh_password = System.getenv("GIT_SSH_PASSWORD")
def git_ssh_private_key = System.getenv("GIT_SSH_PRIVATE_KEY")

def kubeconfigName = 'kubeconfig'
def kubeconfigContent = System.getenv("KUBECONFIG")

// Configure SSH / Git credentials
def global_domain = com.cloudbees.plugins.credentials.domains.Domain.global()
def credentials_store =
  Jenkins.instance.getExtensionList(
    'com.cloudbees.plugins.credentials.SystemCredentialsProvider'
  )[0].getStore()

def key_source
if (git_ssh_private_key.startsWith('-----BEGIN')) {
  key_source = new BasicSSHUserPrivateKey.DirectEntryPrivateKeySource(git_ssh_private_key)
} else {
  key_source = new BasicSSHUserPrivateKey.FileOnMasterPrivateKeySource(git_ssh_private_key)
}

def credentials = new BasicSSHUserPrivateKey(
  CredentialsScope.GLOBAL,
  git_username,
  git_username,
  key_source,
  git_ssh_password,
  git_username
)

// Create or update the credentials in the Jenkins instance
def existing_credentials = credentials_for_username(git_username)

if(existing_credentials != null) {
  credentials_store.updateCredentials(
    global_domain,
    existing_credentials,
    credentials
  )
} else {
  credentials_store.addCredentials(global_domain, credentials)
}

existing_credentials = credentials_for_username(git_username)
def credentialsId = existing_credentials.getId()

def scm = """\
  <scm class="hudson.plugins.git.GitSCM">
    <configVersion>2</configVersion>
    <userRemoteConfigs>
      <hudson.plugins.git.UserRemoteConfig>
        <url><![CDATA[${git_url}]]></url>
        <credentialsId>${credentialsId}</credentialsId>
      </hudson.plugins.git.UserRemoteConfig>
    </userRemoteConfigs>
    <branches>
      <hudson.plugins.git.BranchSpec>
        <name>*/master</name>
      </hudson.plugins.git.BranchSpec>
    </branches>
    <doGenerateSubmoduleConfigurations>false</doGenerateSubmoduleConfigurations>
    <submoduleCfg class="list"/>
    <extensions/>
  </scm>
"""

def configXml = """\
  <?xml version='1.0' encoding='UTF-8'?>
  <project>
    <actions/>
    <description>Create Jenkins jobs from DSL groovy files</description>
    <keepDependencies>false</keepDependencies>
    <properties>
    </properties>
    ${scm}
    <canRoam>true</canRoam>
    <disabled>false</disabled>
    <blockBuildWhenDownstreamBuilding>false</blockBuildWhenDownstreamBuilding>
    <blockBuildWhenUpstreamBuilding>false</blockBuildWhenUpstreamBuilding>
    <triggers/>
    <concurrentBuild>false</concurrentBuild>
    <builders>
      <javaposse.jobdsl.plugin.ExecuteDslScripts plugin="job-dsl@1.37">
        <targets>pipelines/**/*.groovy</targets>
        <usingScriptText>false</usingScriptText>
        <ignoreExisting>false</ignoreExisting>
        <removedJobAction>IGNORE</removedJobAction>
        <removedViewAction>IGNORE</removedViewAction>
        <lookupStrategy>JENKINS_ROOT</lookupStrategy>
        <additionalClasspath></additionalClasspath>
      </javaposse.jobdsl.plugin.ExecuteDslScripts>
    </builders>
    <publishers/>
    <buildWrappers/>
  </project>
""".stripIndent()

job = Jenkins.instance.getItemByFullName(jobName, AbstractItem)
if (!job) {
  def xmlStream = new ByteArrayInputStream( configXml.getBytes() )
  try {
    def seedJob = Jenkins.instance.createProjectFromXML(jobName, xmlStream)
    seedJob.scheduleBuild(0, null)
  } catch (ex) {
    println "ERROR: ${ex}"
    println configXml.stripIndent()
  }
} else {
  def xmlStream = new StreamSource(new ByteArrayInputStream( configXml.getBytes() ))
  job.updateByXml(xmlStream)
}
