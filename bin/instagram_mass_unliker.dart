import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:puppeteer/puppeteer.dart';
import 'package:puppeteer/protocol/network.dart' as net;
import 'package:path/path.dart' as path;

const String version = '0.0.1';

final Directory workDir = Directory('instagram_unliker')..createSync();

final File cookieFile = File(path.join(workDir.path, "unliker_cookies.json"))..createSync();

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
      // Wait for span with specific text using waitForFunction
      await page.waitForFunction(
        '''(text) => {
        const spans = document.querySelectorAll('div[class="wbloks_1"] > span');
        return Array.from(spans).some(span => span.textContent.trim() === text);
      }''',
        args: [buttonText],
        timeout: Duration(seconds: 360),
      );

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

Future<List<ElementHandle>> getButtonsOnPage(final Page page) {
  return page.$$('div[role="button"]');
}

Future<void> applySorting(final Page page) async {
  // get sort button and click it
  final ElementHandle sortButton = await findButton(page: page, buttonText: 'Sortieren und filtern');
  await sortButton.click(delay: Duration(milliseconds: 500));

  // Click sort option: Älteste zuerst
  final ElementHandle sortingButton = await findButton(page: page, buttonText: 'Älteste zuerst');
  await sortingButton.click();

  final ElementHandle applyButton = await findButton(page: page, buttonText: 'Übernehmen');
  await applyButton.click();
}

Future<void> startUnliking(final Page page) async {
  // Click select button
  final ElementHandle selectButton = await findButton(page: page, buttonText: 'Auswählen', isSpan: true);
  await selectButton.click();

  await page.waitForSelector('div[role="button"][aria-label="Image with button"]');

  final ElementHandle unlikeButton = await findButton(page: page, buttonText: 'Gefällt mir nicht mehr');
  // Select the posts and scroll. Do this one hundred at a time. Funnily enough, the posts are buttons.
  final Queue<ElementHandle> posts = Queue.from(await page.$$('div[role="button"][aria-label="Image with button"]'));

  // Filter for all the posts that are labeled "image with button"
  int clickedPosts = 0;
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

      await Future.delayed(Duration(seconds: 2));

      // Check if new posts were loaded
      final List<ElementHandle> loadedPosts = await page.$$('div[role="button"][aria-label="Image with button"]');

      if (loadedPosts.length > previousPostCount) {
        // New posts loaded, update iterator
        posts.addAll(loadedPosts.skip(previousPostCount));
        previousPostCount = loadedPosts.length;
      } else {
        // No new posts - we've reached the end
        print('Reached end of scrollable content');
        break;
      }
    }

    await posts.removeFirst().click(delay: Duration(milliseconds: 200));
    clickedPosts++;
  }

  await unlikeButton.click(delay: Duration(milliseconds: 200));
  // Popup appears, confirm popup
  // Unlike button: ._a9--._ap36._a9_1

  await page.waitForSelector("._a9--._ap36._a9_1");
  final ElementHandle unlikeConfirm = await page.$("._a9--._ap36._a9_1");
  await unlikeConfirm.click(delay: Duration(seconds: 5));
}


void main(List<String> arguments) async {
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

  // Find button to sort and sort accordingly -- first to last
  await applySorting(page);

  while (true) {
    await startUnliking(page);
  }
  await browser.close();
}
