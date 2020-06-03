# Scripts to handle OneVizion installation and upgrades

Supported features:
- Automatic configuration of AWS EC2 instances with [EC2 UserData](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/user-data.html)
- Scripts to configure on prems Linux servers
- Management (add/upgrade/remove) of the OneVizion installs
- Management (add/upgrade/remove) of the additional service instances (report-schedulers, rule-services, etc)
- OneVizion installs collocation

Most scripts are implemented in Bash with some Python 2.7 usage. Latest version of Tomcat 8.5 is installed by default. OneVizion services (reports,mail, etc) are installed as [systemd](https://www.freedesktop.org/wiki/Software/systemd/) daemons.

For documentation on initial configuration of the web and app servers check [setup/initial](setup/initial/README.md) folder

Use install-web.sh, install-daemon-service.sh and install-cron-service.sh to add additional OneVizion installs to the preconfigured server (i.e Tomcat and Java should be already installed).
Use list-services.sh to get configured OneVizion services

Use update-ov.sh to install new version of OneVizion.

To get usage instructions invoke any script without arguments.
