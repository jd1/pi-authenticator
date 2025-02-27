/*
  privacyIDEA Authenticator

  Authors: Timo Sturm <timo.sturm@netknights.it>

  Copyright (c) 2017-2021 NetKnights GmbH

  Licensed under the Apache License, Version 2.0 (the 'License');
  you may not use this file except in compliance with the License.
  You may obtain a copy of the License at

  http://www.apache.org/licenses/LICENSE-2.0

  Unless required by applicable law or agreed to in writing, software
  distributed under the License is distributed on an 'AS IS' BASIS,
  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
  See the License for the specific language governing permissions and
  limitations under the License.
*/

import 'dart:developer';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:http/http.dart';
import 'package:privacyidea_authenticator/model/tokens.dart';
import 'package:privacyidea_authenticator/utils/crypto_utils.dart';
import 'package:privacyidea_authenticator/utils/network_utils.dart';
import 'package:privacyidea_authenticator/utils/push_provider.dart';
import 'package:privacyidea_authenticator/utils/storage_utils.dart';

class UpdateFirebaseTokenDialog extends StatefulWidget {
  @override
  State<StatefulWidget> createState() => _UpdateFirebaseTokenDialogState();
}

class _UpdateFirebaseTokenDialogState extends State<UpdateFirebaseTokenDialog> {
  Widget _content = Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: <Widget>[CircularProgressIndicator()],
  );

  @override
  void initState() {
    super.initState();
    _updateFbTokens();
  }

  @override
  Widget build(BuildContext context) {
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
      child: AlertDialog(
        title: Text(AppLocalizations.of(context)!.synchronizingTokens),
        content: _content,
        actions: <Widget>[
          TextButton(
            child: Text(AppLocalizations.of(context)!.dismiss),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  void _updateFbTokens() async {
    log('Starting update of firebase token.',
        name: 'update_firebase_token_dialog.dart#_updateFbTokens');

    List<PushToken> tokenList =
        (await StorageUtil.loadAllTokens()).whereType<PushToken>().toList();

    // TODO What to do with poll only tokens if google-services is used?

    String? token = await PushProvider.getFBToken();

    // TODO Is there a good way to handle these tokens?
    List<PushToken> tokenWithOutUrl =
        tokenList.where((e) => e.url == null).toList();
    List<PushToken> tokenWithUrl =
        tokenList.where((e) => e.url != null).toList();
    List<PushToken> tokenWithFailedUpdate = [];

    for (PushToken p in tokenWithUrl) {
      // POST /ttype/push HTTP/1.1
      //Host: example.com
      //
      //new_fb_token=<new firebase token>
      //serial=<tokenserial>element
      //timestamp=<timestamp>
      //signature=SIGNATURE(<new firebase token>|<tokenserial>|<timestamp>)

      String timestamp = DateTime.now().toUtc().toIso8601String();

      String message = '$token|${p.serial}|$timestamp';
      String? signature = await trySignWithToken(p, message, context);
      if (signature == null) {
        return;
      }

      Response response;
      try {
        response = await doPost(sslVerify: p.sslVerify!, url: p.url!, body: {
          'new_fb_token': token,
          'serial': p.serial,
          'timestamp': timestamp,
          'signature': signature
        });

        if (response.statusCode == 200) {
          log('Updating firebase token for push token: ${p.serial} succeeded!',
              name: 'update_firebase_token_dialog.dart#_updateFbTokens');
        } else {
          log('Updating firebase token for push token: ${p.serial} failed!',
              name: 'update_firebase_token_dialog.dart#_updateFbTokens');
          tokenWithFailedUpdate.add(p);
        }
      } on SocketException catch (e) {
        log('Socket exception occurred: $e',
            name: 'update_firebase_token_dialog.dart#_updateFbTokens');
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(AppLocalizations.of(context)!
              .errorSynchronizationNoNetworkConnection),
          duration: Duration(seconds: 3),
        ));
        Navigator.pop(context);
        return;
      }
    }

    if (tokenWithFailedUpdate.isEmpty && tokenWithOutUrl.isEmpty) {
      setState(() {
        _content = Text(AppLocalizations.of(context)!.allTokensSynchronized);
      });
    } else {
      List<Widget> children = [];

      if (tokenWithFailedUpdate.isNotEmpty) {
        children.add(Text(AppLocalizations.of(context)!.synchronizationFailed));
        for (PushToken p in tokenWithFailedUpdate) {
          children.add(Text('• ${p.label}'));
        }
      }

      if (tokenWithOutUrl.isNotEmpty) {
        if (children.isNotEmpty) {
          children.add(Divider());
        }

        children.add(Text(
            AppLocalizations.of(context)!.tokensDoNotSupportSynchronization));
        for (PushToken p in tokenWithOutUrl) {
          children.add(Text('• ${p.label}'));
        }
      }

      final ScrollController controller = ScrollController();

      setState(() {
        _content = Scrollbar(
          isAlwaysShown: true,
          controller: controller,
          child: SingleChildScrollView(
            controller: controller,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        );
      });
    }
  }
}
