# QixOS community repository
This is the community repository for [QixOS](https://codeberg.org/originalposter/qixos).
It is meant to be a place where any user of QixOS can share what they built with each other.
Mainly we expect this repo to be filled with various nix configurations that relate specifically to QixOS.
For example specialized nube (nix qubes) configs or modules that can be used in nube configs.

## Make a submission
In order to add your own configs clone this repo and add your configs under a `users/<your name>/` directory and commit the changes and open a pull request.
I'll be lenient in what I allow into this repository as long as it is under your own namespace. Essentially anything that isn't malware is allowed.

## Choose your trust
Be mindful that this repo is not strictly audited and the point is that many different contributors can add code here.
Treat each name under the `user/` directory as different users with completely different trust levels and be mindful of who you are choosing to trust.

## Document security risks
Sometimes we want to create configs that make security tradeoffs for some reason. If you do this then please document this clearly.
Describe what the user of your code will give up in terms of security and describe why this is necessary to achieve what you're trying to achieve.
