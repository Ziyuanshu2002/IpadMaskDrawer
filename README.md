# IpadMaskDrawer
segmentation mask generation is rather uncomfortable on PC. This app allow you to draw your own segmentation masks on iPad which is significantly easier in my experience great for generating training dataset. Inrease the throughput and comfort for generating training dataset for segmentation mask.

# Rquirement
  Currently the version is in beta and you will need both an Ipad and an a Mac to my knowledge.
  Once Published you should be able to download it on AppStore

# Download and Installation
Download the contentview.swift. Download Xcode at https://developer.apple.com/xcode/. 
<img width="764" height="344" alt="image" src="https://github.com/user-attachments/assets/e0b126b0-be04-4a26-a7ac-acbdcd4f7d7e" />
Follow the apple protocol to turn on developer mode on your Ipad.
https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device
Then connect your Ipad to your Mac through data cable. Xcode should prompt that your Ipad is good for testing purposed. 
Choose your IPad in the device selection
<img width="352" height="28" alt="image" src="https://github.com/user-attachments/assets/5a1a5ba3-6802-4173-acd7-5cb478dde915" />
Hit run
<img width="221" height="25" alt="image" src="https://github.com/user-attachments/assets/961e43f9-4cff-4a03-b0f9-ab064f31c0f1" />
If you don't already have personal developing license, you are expected to create a free developer license with your apple id. Once created select the license forr your project in Xcode.
Trust yourself in the privacy&security license in ipad. Then you should be good to go
Notice that one installation is valid for 7 days if you have membership with apple it will last longer.
Once beta is over, it should be avaliable to download on applestore.

# Usage
Rearrange your timeseries data or all masks in BF#.tif format (BF1.tif, BF2.tif....) and save it in a folder. use the choose folder version on your ipad to choose the folder.
Then the program should autogenerate a blank masks for all images (it works for iCloud but extremely slow, try avoid especially in large quantity)
You can choose 5 different labels with the label function and change brush pixel size. And eraser is toggled on or off. Pencil Only can be toggled on so only apple pencil can make changes to the mask to prevent mistouch.
Save Mask TIFF- save current mask.
Next- move to next frame and save the mask.
Autofill- toggled on and off. When On, hitting the save Mask TIFF or Next function will automatically fill the label that is enclosed.
Clear Mask- remove all label in the current frame.

# Pending function
Zoom in and out and lock Zoom function(for time series).
Any suggestion
