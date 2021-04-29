## AWSDeployCore
Deploy an AWS Lambda from Xcode.

* Create a new executable target that depends on `AWSDeployCore`
* Switch your target in Xcode to your new target
* Press `cmd` + `shift` + `<` to edit the scheme
* Add the path to your project in the "Arguments Passed On Launch" section.

Now when you want to deploy, simply pick your new target and run. Logs should appear in the Xcode console. 
