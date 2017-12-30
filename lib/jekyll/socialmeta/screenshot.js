"use strict";
var system = require('system');
var myBase = system.env['site_base'];
var page = require('webpage').create(),
    address, output, origin, imgTop, imgLeft, dimensions, imgWidth, imgHeight,
    viewDimensions, viewWidth, viewHeight, scroll, scrollTop, scrollLeft,
    zoom, bgStyle, imgStyle;

/*page.onResourceRequested = function (request) {
    system.stderr.writeLine('= onResourceRequested()');
    system.stderr.writeLine('  request: ' + JSON.stringify(request, undefined, 4));
};
 
page.onResourceReceived = function(response) {
    system.stderr.writeLine('= onResourceReceived()' );
    system.stderr.writeLine('  id: ' + response.id + ', stage: "' + response.stage + '", response: ' + JSON.stringify(response));
};
 
page.onLoadStarted = function() {
    system.stderr.writeLine('= onLoadStarted()');
    var currentUrl = page.evaluate(function() {
        return window.location.href;
    });
    system.stderr.writeLine('  leaving url: ' + currentUrl);
};
 
page.onLoadFinished = function(status) {
    system.stderr.writeLine('= onLoadFinished()');
    system.stderr.writeLine('  status: ' + status);
};
 
page.onNavigationRequested = function(url, type, willNavigate, main) {
    system.stderr.writeLine('= onNavigationRequested');
    system.stderr.writeLine('  destination_url: ' + url);
    system.stderr.writeLine('  type (cause): ' + type);
    system.stderr.writeLine('  will navigate: ' + willNavigate);
    system.stderr.writeLine('  from page\'s main frame: ' + main);
};


page.onResourceError = function(resourceError) {
    system.stderr.writeLine('= onResourceError()');
    system.stderr.writeLine('  - unable to load url: "' + resourceError.url + '"');
    system.stderr.writeLine('  - error code: ' + resourceError.errorCode + ', description: ' + resourceError.errorString );
};
 
page.onError = function(msg, trace) {
    system.stderr.writeLine('= onError()');
    var msgStack = ['  ERROR: ' + msg];
    if (trace) {
        msgStack.push('  TRACE:');
        trace.forEach(function(t) {
            msgStack.push('    -> ' + t.file + ': ' + t.line + (t.function ? ' (in function "' + t.function + '")' : ''));
        });
    }
    system.stderr.writeLine(msgStack.join('\n'));
};
*/

page.onResourceError = function(resourceError) {
  //system.stderr.writeLine('Error!');
  //system.stderr.writeLine(JSON.stringify(resourceError, null, 2));
  system.stdout.writeLine('debug '+resourceError.errorString+': '+resourceError.url);
  page.reason_url = resourceError.url;
  page.reason = resourceError.errorString;
};


address = system.args[1];
output = system.args[2];
origin = system.args[3];
dimensions  = system.args[4];
viewDimensions = system.args[5];
scroll = system.args[6];
zoom = parseFloat(system.args[7]);
bgStyle = system.args[8];
imgStyle = system.args[9];

var tmp = origin.split(',');
imgTop = parseInt(tmp[0]);
imgLeft = parseInt(tmp[1]);

tmp = dimensions.split('x');
imgWidth = parseInt(tmp[0]);
imgHeight = parseInt(tmp[1]);

tmp = viewDimensions.split('x');
viewWidth = parseInt(tmp[0]);
viewHeight = parseInt(tmp[1]);

tmp = scroll.split(',');
scrollTop = parseInt(tmp[0]);
scrollLeft = parseInt(tmp[1]);

system.stderr.writeLine('Hello!');
system.stderr.writeLine('------');
system.stderr.writeLine('myBase: '+myBase);

system.stderr.writeLine('height: '+imgHeight);
system.stderr.writeLine('width: '+imgWidth);
system.stderr.writeLine('viewHeight: '+viewHeight);
system.stderr.writeLine('viewWidth: '+viewWidth);
system.stderr.writeLine('scrollTop: '+scrollTop);
system.stderr.writeLine('scrollLeft: '+scrollLeft);
system.stderr.writeLine('imgStyle: '+imgStyle);
system.stderr.writeLine('bgStyle: '+bgStyle);
system.stderr.writeLine('zoom: '+zoom);

//page.settings.userAgent = 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/28.0.1500.71 Safari/537.36';
//page.settings.userAgent = 'Mozilla/5.0 (Unknown; Linux x86_64) AppleWebKit/538.1 (KHTML, like Gecko) Safari/538.1';

system.stderr.writeLine('address='+address);
system.stderr.writeLine('output='+output);
////system.stderr.writeLine('size='+pageWidth+'x'+pageHeight);
//system.stderr.writeLine('top='+pageTop);

//page.viewportSize = { width: pageWidth, height: pageHeight };
page.viewportSize = { width: viewWidth, height: viewHeight};
page.clipRect = { top: imgTop, left: imgLeft, width: imgWidth, height: imgHeight };

// Doesn't work?
// Worked-around with top and left
//page.scrollPosition = { top: scrollTop, left: scrollLeft };

page.zoomFactor = zoom;

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
      page.evaluate ( function(bgStyle, imgStyle) {
        document.body.style.cssText += bgStyle;
        var imgs = document.body.getElementsByTagName("img");
        imgs[0].style.cssText += imgStyle;
      }, bgStyle, imgStyle);

      page.render(output, {format: 'jpg', quality: '100'});

      system.stderr.writeLine('');
      system.stderr.writeLine('PAGE:');
      system.stderr.writeLine(page.content);
      system.stderr.writeLine('');
      phantom.exit();
    }, 200);
  }
});
