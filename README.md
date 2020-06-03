# Support scripts to handle OneVizion platform initial installation and upgrades

Supported features:
- Automatic configuration of AWS EC2 instances with [EC2 UserData](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/user-data.html)
- Scripts to configure on prems Linux servers
- Management (add/upgrade/remove) of the OneVizion installs
- Management (add/upgrade/remove) of the additional service instances (report-schedulers, rule-services, etc)
- OneVizion installs collocation

Most scripts are implemented in Bash with some Python 2.7 usage.

For documentation on initial configuration of the web and app servers check [setup/initial folder](setup/initial/README.md)

Use install-web.sh, install-daemon-service.sh and install-cron-service.sh to add additional OneVizion installs to the preconfigured server (i.e Tomcat and Java should be already installed).
Use list-services.sh to get configured OneVizion services

Use update-ov.sh to install new version of OneVizion.

To get usage instructions invoke any script without arguments.