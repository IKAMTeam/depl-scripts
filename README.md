# Scripts to handle OneVizion installation and upgrades

### Supported features:
- Automatic configuration of AWS EC2 instances with [EC2 UserData](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/user-data.html)
- Scripts to configure on prems Linux servers
- Management (add/upgrade/remove) of the OneVizion installs
- Management (add/upgrade/remove) of the additional service instances (report-schedulers, rule-services, etc)
- OneVizion installs collocation
- Amazon Linux 2023 is supported (Amazon Linux 2 is not)

Most scripts are implemented in Bash with some Python 3 usage. Latest version of Tomcat 10 is installed by default. OneVizion services (reports,mail, etc) are installed as [systemd](https://www.freedesktop.org/wiki/Software/systemd/) daemons.

For documentation on initial configuration of the web and app servers check [setup/initial](setup/initial/README.md) folder.

Use `install-web.sh`, `install-daemon-service.sh` and `install-cron-service.sh` to add additional OneVizion installs to the preconfigured server (i.e Tomcat and Java should be already installed).
Use `list-services.sh` to get configured OneVizion services.

Use `update-ov.sh` to install new version of OneVizion.

To get usage instructions invoke any script without arguments.


### Versioning
As usual, all completed and tested changes are merged into the `master` branch. We use this branch for nightly deployments and selected UAT environments to further test changes in environments close to production. 
When we confident with the `master` branch all changes are merged into the `stable` branch, which is default for production environments. 

As OneVizion platform configuration requirements evolve over time, depl-scripts follow these changes. This means code in the `stable` branch is up to date with the current platform version.
To be able to use depl-scripts with ESR or older versions of the platform, git tags are created. The tag follows the OneVizion platform version, end highlights depl-scripts codebase to be used with the same or newer platform version. 
For example, there are following tags in depl-scripts: `23.8`, `23.2`, `22.25`. Thus, for OneVizion 23.3.0 version, as well as for other versions starting 23.2 to 23.7, depl-script code from the 23.2 must be used.

