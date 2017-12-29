"use strict";
var page = require('webpage').create(),
    system = require('system'),
    address, output, pngTop, pngLeft, pngWidth, pngHeight, viewWidth, viewHeight, zoom;

address = system.args[1];
output = system.args[2];
pngTop = parseInt(system.args[3]);
pngLeft = parseInt(system.args[4]);
pngWidth = parseInt(system.args[5]);
pngHeight = parseInt(system.args[6]);
viewWidth = parseInt(system.args[7]);
viewHeight = parseInt(system.args[8]);
zoom = parseFloat(system.args[9]);

system.stderr.writeLine('zoom is '+zoom)
//page.settings.userAgent = 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/28.0.1500.71 Safari/537.36';

//system.stderr.writeLine('address='+address);
//system.stderr.writeLine('output='+output);
////system.stderr.writeLine('size='+pageWidth+'x'+pageHeight);
//system.stderr.writeLine('top='+pageTop);

//page.viewportSize = { width: pageWidth, height: pageHeight };
page.viewportSize = { width: viewWidth, height: viewHeight};
page.clipRect = { top: pngTop, left: pngLeft, width: pngWidth, height: pngHeight };
page.zoomFactor = zoom;

page.onResourceError = function(resourceError) {
  //system.stderr.writeLine('Error!');
  //system.stderr.writeLine(JSON.stringify(resourceError, null, 2));
  system.stdout.writeLine('debug '+resourceError.errorString+': '+resourceError.url);
  page.reason_url = resourceError.url;
  page.reason = resourceError.errorString;
};

//system.stderr.writeLine('Opening '+address);

page.open(address, function(status) {
  if(status !== 'success') {
    //system.stderr.writeLine('status: '+status);
    //system.stderr.writeLine('Unable to open '+page.reason_url+': '+page.reason)
    system.stdout.writeLine('error Unable to render '+address)
    system.stdout.writeLine('error '+page.reason+' at '+page.reason_url)
    phantom.exit(1);
  } else {
    window.setTimeout(function () {
      /*page.evaluate ( function() {
        var imgs = document.body.getElementsByTagName("img");
        imgs[0].style.cssText = "border: 2px solid white";
      });*/
      page.render(output, {format: 'jpg', quality: '100'});
      //page.render(output);
      system.stderr.writeLine(page.content);
      phantom.exit();
    }, 200);
  }
});
