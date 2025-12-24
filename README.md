# Instagram Mass Unliker

Automates the process of unliking your liked Instagram-Posts, going from oldest to newest.
Selects 90 liked posts at a time and automatically unlikes them. Afterward, the page is refreshed and the process starts all over, until the program is terminated.
Works pretty well as of December 2025. Because the liked-post site is subject to change, the program might break at any time. 

### Setup
Standard Dart setup. Configure the Dart SDK and pull the project's dependencies using _pub_. There's no standalone executable and I don't plan on releasing one for the time being.
For now, there are only two locales: English and German. If you wish to add a new one, the process is dead simple, just add the appropriate button-texts to a new config and supply it via source code.

### Caveats
I made this program for myself, this isn't fully-fledged software. 
I'm not aware that using this automation leads to account-bans or shadowbans. As there has not been extensive testing beyond 20.000 unliked posts,
use it at your own risk.
The Instagram UI really isn't that efficient and load times are unpredictable. I've tried to make the program as self-recovering as possible, but edge-cases 
persist and sometimes timeouts and unexpected behavior happen. At times the program crashes on the first try, sometimes after several hours of running. Take that as you may. 


### Speed and Efficiency 
With the standard config under `/instagram_unliker` it takes about 25-30 seconds to delect and unlike 90 posts. Depending on the amount of posts, you want to have unliked,
this process might take several hours to days.

