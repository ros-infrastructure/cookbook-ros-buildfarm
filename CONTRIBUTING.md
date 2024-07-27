## Release Policy

Changes to this project should be released as soon as they are ready for general use.

Continuous integration tests that the latest changes will converge successfully on each build but there is no automated testing for upgrading existing infrastructure to newer releases of this cookbook.

When making a new release use the following criteria to evaluate which version number to increment:

### Major version (1.2.0 -> 2.0.0)
* Significant changes, breaking or otherwise.
* Removal of deprecated actions or resources.

### Minor version (1.1.0 -> 1.2.0)
* Noteworthy changes
* Compatible improvements
* Deprecation of actions or resources

### Patch version (1.0.1 -> 1.0.2)
* Compatible bug fixes
* Documentation or comment text changes

