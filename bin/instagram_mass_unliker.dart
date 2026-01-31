import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:puppeteer/puppeteer.dart';
import 'package:puppeteer/protocol/network.dart' as net;
import 'package:path/path.dart' as path;

const String version = '0.0.1';

final Directory workDir = Directory('instagram_unliker')..createSync();

final File configFile = File(path.join(workDir.path, "config_de.json"));
final File cookieFile = File(path.join(workDir.path, "unliker_cookies.json"))..createSync();

// Yeah, this sucks, but works
final dynamic config = jsonDecode(configFile.readAsStringSync());

Future<List<CookieParam>> grabCookiesFromLastSession() async {
  final List<CookieParam> cookies = [];
  final String encodedJson = await cookieFile.readAsString();

  if (encodedJson.isEmpty) {
    return List.empty();
  }

  dynamic json = jsonDecode(encodedJson);

  for (dynamic value in json) {
    cookies.add(CookieParam.fromJson(value));
  }

  return cookies;
}

Future<void> dumpCookiesFromSession(final List<net.Cookie> cookies) async {
  final String encodedJson = jsonEncode(cookies);
  await cookieFile.writeAsString(encodedJson);
}

Future<ElementHandle> findButton({required Page page, required String buttonText, bool isSpan = false}) async {
  if (isSpan) {
    if (isSpan) {
      // After 30 seconds we reload the page and try again by resorting and then continuing
      final Timer waitFuture = Timer(Duration(seconds: 30), () async {
        await page.reload();
        await applySorting(page);
      });

      // Wait for span with specific text using waitForFunction
      await page.waitForFunction(
        '''(text) => {
        const spans = document.querySelectorAll('div[class="wbloks_1"] > span');
        return Array.from(spans).some(span => span.textContent.trim() === text);
      }''',
        args: [buttonText],
        timeout: Duration(seconds: 360),
      );

      waitFuture.cancel();

      // Now find and return the matching span
      final List<ElementHandle> spans = await page.$$('div[class="wbloks_1"] > span');

      for (final span in spans) {
        final textProp = await span.property('textContent');
        final text = await textProp.jsonValue;
        if (text != null && text.toString().trim() == buttonText) {
          return span;
        }
      }

      return Future.error("Could not find span with text $buttonText.");
    }
  }

  final ElementHandle? handle = await page.waitForSelector('div[role="button"][aria-label="$buttonText"]');

  if (handle != null) {
    return handle;
  }

  return Future.error("Could not find button with text $buttonText.");
}

Future<void> applySorting(final Page page) async {
  // get sort button and click it
  final ElementHandle sortButton = await findButton(page: page, buttonText: config['sort_button_text']);
  await sortButton.click(delay: Duration(milliseconds: 500));

  // Click sort option: Älteste zuerst
  final ElementHandle sortingButton = await findButton(page: page, buttonText: config['sort_option_button_text']);
  await sortingButton.click();

  final ElementHandle applyButton = await findButton(page: page, buttonText: config['appy_button_text']);
  await applyButton.click();
}

Future<List<ElementHandle>> grabPosts(final Page page) async {
  await page.waitForSelector('div[role="button"][aria-label="Image with button"]');

  // Check if new posts were loaded
  final List<ElementHandle> loadedPosts = await page.$$('div[role="button"][aria-label="Image with button"]');

  return loadedPosts;
}

Future<void> startUnliking(final Page page) async {
  // Click select button
  final ElementHandle selectButton = await findButton(page: page, buttonText: config['select_button_text'], isSpan: true);
  await selectButton.click();

  // Sometimes the button is clicked before it appears, triggering nothing.
  // Retry after about 10 seconds if the click succeeded
  Timer reClickTimer = Timer(Duration(milliseconds: config['re_click_timer_delay']), () async {
    print("Re-Click timer hit.");
    await selectButton.click();
  });

  // wait for the clickable tiles to show up
  await page.waitForSelector('div[role="button"][aria-label="Image with button"]');
  // Tiles showed up -> Button has been pressed successfully -> Cancel the re-click.
  reClickTimer.cancel();

  final ElementHandle unlikeButton = await findButton(page: page, buttonText: config['unlike_button_text']);

  // Select the posts and scroll. Do this one hundred at a time.
  final Queue<ElementHandle> posts = Queue.from(await grabPosts(page));

  int clickedPosts = 0;
  // Skip the posts we've already selected.
  int previousPostCount = posts.length;

  while (clickedPosts < 90) {
    if (posts.isEmpty) {
      // Scroll to bottom of the scrollable div
      await page.evaluate('''() => {
      const scrollableSection = document.querySelector('.wbloks_1.wbloks_92.wbloks_90');
      if (scrollableSection) {
        scrollableSection.scrollTop = scrollableSection.scrollHeight;
      }
    }''');

      await Future.delayed(Duration(seconds: 10));

      // Check if new posts were loaded
      final List<ElementHandle> loadedPosts = await grabPosts(page);

      if (loadedPosts.length > previousPostCount) {
        // New posts loaded, update iterator
        posts.addAll(loadedPosts.skip(previousPostCount));
        previousPostCount = loadedPosts.length;
      } else {
        // No new posts - we've reached the end
        print('Reached end of scrollable content.');
        break;
      }
    }

    try {
      await posts.removeFirst().click(delay: Duration(milliseconds: config['selection_delay']));
      clickedPosts++;
    } catch (e) {
      // Ignore exceptions, just skip to the next element. Click might not be valid because of "null"-posts
      print(e);
    }
  }

  await unlikeButton.click(delay: Duration(milliseconds: config['selection_delay']));
  // Popup appears, confirm popup
  // Unlike button: ._a9--._ap36._a9_1

  await page.waitForSelector("._a9--._ap36._a9_1");
  final ElementHandle unlikeConfirm = await page.$("._a9--._ap36._a9_1");
  await unlikeConfirm.click(delay: Duration(seconds: 5));
}

void main(List<String> arguments) async {
  if (!await configFile.exists()) {
    print("Please configure the program with the appropriate config");
    exit(-1);
  }

  // https://www.instagram.com/your_activity/interactions/likes/

  var browser = await puppeteer.launch(headless: false);
  // Do something...
  final Page page = await browser.newPage();

  // navigate to the instagram url
  // Try to get cookies from the last time the unliker has been started.

  final List<CookieParam> optionalCookies = await grabCookiesFromLastSession();
  if (optionalCookies.isNotEmpty) {
    page.setCookies(optionalCookies);
  }

  await page.goto("https://www.instagram.com/your_activity/interactions/likes");

  if (optionalCookies.isEmpty) {
    // wait for the user to input the credentials. Save to cookie jar for authentication next time
    await page.waitForNavigation(timeout: Duration.zero);
    await dumpCookiesFromSession(await page.cookies());
  }

  while (true) {
    // Find button to sort and sort accordingly -- first to last
    await applySorting(page);

    await startUnliking(page);

    await page.reload();
  }
  await browser.close();
}
