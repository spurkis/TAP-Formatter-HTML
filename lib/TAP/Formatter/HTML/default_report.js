/******************************************************************************
 * TAP-Formatter-HTML: default javascript for report
 * Copyright (c) 2008 Steve Purkis.  All rights reserved.
 * Released under the same terms as Perl itself.
 *****************************************************************************/

jQuery.fn.extend({
  scrollTo : function(speed, easing) {
    return this.each(function() {
      var targetOffset = $(this).offset().top;
      $('html,body').animate({scrollTop: targetOffset}, speed, easing);
    });
  }
});

$(document).ready(function(){
	$("div.test-detail").hide();
	$("div.summary").find("a").click(function(){return false;});

	// expand test detail when user clicks on a test file
	$("a.file").click(function(){
		// go all the way to the tr incase table structure changes:
		$(this).parents("tr:first").find("div.test-detail").slideToggle();
		return false;
	});

	// expand test detail when user clicks on an individual test
	$("a.TS").click(function(){
		var testId = $(this).attr("href")
		// go all the way to the tr incase table structure changes:
		var $detail = $(this).parents("td.results").parents("tr:first").find("div.test-detail");
		$detail.filter(":hidden").slideDown();
		var $testElem = $detail.find(testId);
		$testElem.show().scrollTo(1000);
		var bgColor = $testElem.css("background-color");
		$testElem.css({ backgroundColor: "yellow" });
		// shame you can't animate bg color w/o a plugin...
		setTimeout(function(){$testElem.css({ backgroundColor: bgColor })}, 3000);
		return false;
	});

	// add a toggle to display all/failed tests
	$("div#detail")
	    .append('<div style="float: right; width: 40px; font-size: small; text-align: right;">'+
		    '<span id="show-all" style="display: none"><a href="#" title="show all tests" ' +
		    'onClick="$(\'tr.passed\').show(); $(\'#show-all\').hide(); $(\'#show-failed\').show(); return false;">all</a>' +
		    '</span><span id="show-failed"><a href="#" title="show failed tests only" ' +
		    'onClick="$(\'tr.passed\').hide(); $(\'#show-failed\').hide(); $(\'#show-all\').show(); return false;">failed</a>' +
		    '</span></div>');
});
