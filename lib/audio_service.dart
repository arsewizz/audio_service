import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The different buttons on a headset.
enum MediaButton {
  media,
  next,
  previous,
}

/// The actons associated with playing audio.
enum MediaAction {
  stop,
  pause,
  play,
  rewind,
  skipToPrevious,
  skipToNext,
  fastForward,
  setRating,
  seekTo,
  playPause,
  playFromMediaId,
  playFromSearch,
  skipToQueueItem,
  playFromUri,
}

/// The different states during audio playback.
enum PlaybackState {
  none,
  stopped,
  paused,
  playing,
  fastForwarding,
  rewinding,
  buffering,
  error,
  connecting,
  skippingToPrevious,
  skippingToNext,
  skippingToQueueItem,
}

/// Metadata about an audio item that can be played, or a folder containing
/// audio items.
class MediaItem {
  String id;
  String album;
  String title;
  bool playable;

  MediaItem(
      {@required this.id,
      @required this.album,
      @required this.title,
      this.playable = true});
}

/// A button that controls audio playback.
class MediaControl {
  String androidIcon;
  String label;
  MediaAction action;

  MediaControl({this.androidIcon, @required this.label, @required this.action});
}

const MethodChannel _channel =
    const MethodChannel('ryanheise.com/audioService');

List<Map> _mediaItems2raw(List<MediaItem> list) => list
    .map((mediaItem) => {
          'id': mediaItem.id,
          'album': mediaItem.album,
          'title': mediaItem.title,
          'playable': mediaItem.playable,
        })
    .toList();

Map _mediaItem2raw(MediaItem mediaItem) => {
      'id': mediaItem.id,
      'album': mediaItem.album,
      'title': mediaItem.title,
      'playable': mediaItem.playable,
    };

const String _CUSTOM_PREFIX = 'custom_';

/// A callback to handle playback state changes.
typedef OnPlaybackStateChanged = void Function(
    PlaybackState state, int position, double speed, int updateTime);

/// A callback to handle media item changes.
typedef OnMediaChanged = void Function(int mediaId);

/// A callback to handle queue changes.
typedef OnQueueChanged = void Function(List<MediaItem> queue);

/// Client API to start and interact with the audio service.
///
/// This class is used from your UI code to establish a connection with the
/// audio service. While connected to the service, your UI may invoke methods
/// of this class to start/pause/stop/etc. playback and listen to changes in
/// playback state and playing media.
///
/// Your UI must disconnect from the audio service when it is no longer visible
/// although the audio service will continue to run in the background. If your
/// UI once again becomes visible, you should reconnect to the audio service.
class AudioService {
  static OnPlaybackStateChanged _onPlaybackStateChanged;
  static OnMediaChanged _onMediaChanged;
  static OnQueueChanged _onQueueChanged;

  /// Connects to the service from your UI to start and control audio playback.
  ///
  /// [onPlaybackStateChanged] will be called whenever the playback state has
  /// changed but will also be called once on startup to report the initial
  /// playback state. [onMediaChanged] will be called whenever the playing
  /// media has changed, and also once on startup to report the initial media.
  /// [onQueueChanged] will be called whenever the queue has changed, and also
  /// once on startup to report the initial queue.
  static Future<void> connect(
      {OnPlaybackStateChanged onPlaybackStateChanged,
      OnMediaChanged onMediaChanged,
      OnQueueChanged onQueueChanged}) async {
    _onPlaybackStateChanged = onPlaybackStateChanged;
    _onMediaChanged = onMediaChanged;
    _onQueueChanged = onQueueChanged;
    _channel.setMethodCallHandler((MethodCall call) {
      switch (call.method) {
        case 'onPlaybackStateChanged':
          if (_onPlaybackStateChanged != null) {
            final List args = call.arguments;
            _onPlaybackStateChanged(
                PlaybackState.values[args[0]], args[1], args[2], args[3]);
          }
          break;
        case 'onMediaChanged':
          if (_onMediaChanged != null) {
            _onMediaChanged(call.arguments[0]);
          }
          break;
        case 'onQueueChanged':
          if (_onQueueChanged != null) {
            final List<Map> args = call.arguments;
            List<MediaItem> queue = args
                .map((raw) => MediaItem(
                    id: raw['id'], title: raw['title'], album: raw['album']))
                .toList();
            _onQueueChanged(queue);
          }
          break;
      }
    });
    await _channel.invokeMethod("connect");
  }

  /// Disconnects your UI from the service.
  static Future<void> disconnect() async {
    await _channel.invokeMethod("disconnect");
  }

  /// True if the background audio task is running.
  static Future<bool> get running async {
    return await _channel.invokeMethod("isRunning");
  }

  /// Starts a background audio task which will continue running even when the
  /// UI is not visible or the screen is turned off.
  ///
  /// The background task is specified by [backgroundTask] which will be run
  /// within a background isolate. This function must be a top-level or static
  /// function, and it must initiate execution by calling
  /// [AudioServiceBackground.run].
  ///
  /// On Android, this will start a `MediaBrowserService` in the foreground
  /// along with a notification. The Android notification icon is specified
  /// like an XML resource reference and defaults to `"mipmap/ic_launcher"`. If
  /// your audio player will manage a playlist, you may specify the initial
  /// playlist with [queue] and request to modify it from the client side via
  /// [addQueueItem], [addQueueItemAt] and [removeQueueItem].
  static Future<bool> start({
    @required Function backgroundTask,
    String notificationChannelName = "Notifications",
    int notificationColor,
    String androidNotificationIcon = 'mipmap/ic_launcher',
    bool resumeOnClick = true,
    List<MediaItem> queue = const <MediaItem>[],
  }) async {
    final ui.CallbackHandle handle =
        ui.PluginUtilities.getCallbackHandle(backgroundTask);
    if (handle == null) {
      return false;
    }
    var callbackHandle = handle.toRawHandle();
    return await _channel.invokeMethod('start', {
      'callbackHandle': callbackHandle,
      'notificationChannelName': notificationChannelName,
      'notificationColor': notificationColor,
      'androidNotificationIcon': androidNotificationIcon,
      'resumeOnClick': resumeOnClick,
      'queue': _mediaItems2raw(queue),
    });
  }

  /// Passes through to `onAddQueueItem` in the background task.
  static Future<void> addQueueItem(MediaItem mediaItem) async {
    await _channel.invokeMethod('addQueueItem', _mediaItem2raw(mediaItem));
  }

  /// Passes through to `onAddQueueItemAt` in the background task.
  static Future<void> addQueueItemAt(MediaItem mediaItem, int index) async {
    await _channel
        .invokeMethod('addQueueItemAt', [_mediaItem2raw(mediaItem), index]);
  }

  /// Passes through to `onRemoveQueueItem` in the background task.
  static Future<void> removeQueueItem(MediaItem mediaItem) async {
    await _channel.invokeMethod('removeQueueItem', _mediaItem2raw(mediaItem));
  }

  /// Programmatically simulates a click of a media button on the headset.
  ///
  /// This passes through to `onClick` in the background task.
  static Future<void> click([MediaButton button = MediaButton.media]) async {
    await _channel.invokeMethod('click', button.index);
  }

  /// Passes through to `onPrepare` in the background task.
  static Future<void> prepare() async {
    await _channel.invokeMethod('prepare');
  }

  /// Passes through to `onPrepareFromMediaId` in the background task.
  static Future<void> prepareFromMediaId(String mediaId) async {
    await _channel.invokeMethod('prepareFromMediaId', mediaId);
  }

  //static Future<void> prepareFromSearch(String query, Bundle extras) async {}
  //static Future<void> prepareFromUri(Uri uri, Bundle extras) async {}

  /// Passes through to 'onPlay' in the background task.
  static Future<void> play() async {
    await _channel.invokeMethod('play');
  }

  //static Future<void> playFromMediaId(String mediaId, Bundle extras) async {}
  //static Future<void> playFromSearch(String query, Bundle extras) async {}
  //static Future<void> playFromUri(Uri uri, Bundle extras) async {}

  /// Passes through to `skipToQueueItem` in the background task.
  static Future<void> skipToQueueItem(int id) async {
    await _channel.invokeMethod('skipToQueueItem');
  }

  /// Passes through to `onPause` in the background task.
  static Future<void> pause() async {
    await _channel.invokeMethod('pause');
  }

  /// Passes through to `onStop` in the background task.
  static Future<void> stop() async {
    await _channel.invokeMethod('stop');
  }

  /// Passes through to `onSeekTo` in the background task.
  static Future<void> seekTo(int pos) async {
    await _channel.invokeMethod('seekTo', pos);
  }

  //static Future<void> fastForward() async {}

  // Passes through to `onSkipToNext` in the background task.
  static Future<void> skipToNext() async {
    await _channel.invokeMethod('skipToNext');
  }

  //static Future<void> rewind() async {}

  // Passes through to `onSkipToPrevious` in the background task.
  static Future<void> skipToPrevious() async {
    await _channel.invokeMethod('skipToPrevious');
  }

  //static Future<void> setRating(RatingCompat rating) async {}
  //static Future<void> setRating(RatingCompat rating, Bundle extras) async {}
  //static Future<void> setCaptioningEnabled(boolean enabled) async {}
  //static Future<void> setRepeatMode(@PlaybackStateCompat.RepeatMode int repeatMode) async {}
  //static Future<void> setShuffleMode(@PlaybackStateCompat.ShuffleMode int shuffleMode) async {}
  //static Future<void> sendCustomAction(PlaybackStateCompat.CustomAction customAction,
  //static Future<void> sendCustomAction(String action, Bundle args) async {}

  /// Passes through to `onCustomAction` in the background task.
  ///
  /// This may be used for your own purposes.
  static Future customAction(String name, [dynamic arguments]) async {
    return await _channel.invokeMethod('$_CUSTOM_PREFIX$name', arguments);
  }
}

/// Background API to be used by your background audio task.
///
/// The background task that you passed to [AudioService.start] is executed in
/// an isolate that will run independently of the view. Aside from its primary
/// job of playing audio, your background task should also use methods of this
/// class to initialise the isolate, broadcast state changes to any UI that may
/// be connected, and to also handle playback actions initiated by the UI.
class AudioServiceBackground {
  static MethodChannel _backgroundChannel;
  static PlaybackState _state;

  /// The current media playback state.
  ///
  /// This is the value most recently set via [setState].
  static PlaybackState get state => _state;

  /// Initialises the isolate in which your background task runs.
  ///
  /// Each callback function you supply handles an action initiated from a
  /// connected client. In particular:
  ///
  /// [onStart] (required) is an asynchronous function that is called in
  /// response to [AudioService.start]. It is responsible for starting audio
  /// playback and should not complete until there is no more audio to be
  /// played. Once this function completes, the background isolate will be
  /// permanently shut down (although a new one can be started by calling
  /// [AudioService.start] again).
  ///
  /// [onStop] (required) is called in response to [AudioService.stop] (or the
  /// stop button in the notification or Wear OS or Android Auto). It is
  /// [onStop]'s responsibility to perform whatever code is necessary to cause
  /// [onStart] to complete. This may be done by using a [Completer] or by
  /// setting a flag that will trigger a loop in [onStart] to complete.
  ///
  /// [onPause] is called in response to [AudioService.pause], or the pause
  /// button in the notification or Wear OS or Android Auto.
  ///
  /// [onClick] is called in response to [AudioService.click], or if a media
  /// button is clicked on the headset.
  static Future<void> run({
    @required Future<void> onStart(),
    Future<List<MediaItem>> onLoadChildren(),
    VoidCallback onAudioFocusGained,
    VoidCallback onAudioFocusLost,
    VoidCallback onAudioFocusLostTransient,
    VoidCallback onAudioFocusLostTransientCanDuck,
    VoidCallback onAudioBecomingNoisy,
    void onClick(MediaButton button),
    @required VoidCallback onStop,
    VoidCallback onPause,
    VoidCallback onPrepare,
    ValueChanged<String> onPrepareFromMediaId,
    VoidCallback onPlay,
    ValueChanged<String> onPlayFromMediaId,
    ValueChanged<String> onAddQueueItem,
    void onAddQueueItemAt(String mediaId, int index),
    ValueChanged<String> onRemoveQueueItem,
    VoidCallback onSkipToNext,
    VoidCallback onSkipToPrevious,
    ValueChanged<int> onSkipToQueueItem,
    ValueChanged<int> onSeekTo,
    void onCustomAction(String name, dynamic arguments),
  }) async {
    _backgroundChannel =
        const MethodChannel('ryanheise.com/audioServiceBackground');
    WidgetsFlutterBinding.ensureInitialized();
    _backgroundChannel.setMethodCallHandler((MethodCall call) async {
      switch (call.method) {
        case 'onLoadChildren':
          if (onLoadChildren != null) {
            List<MediaItem> mediaItems = await onLoadChildren();
            List<Map> rawMediaItems = mediaItems
                .map((mediaItem) => {
                      'id': mediaItem.id,
                      'album': mediaItem.album,
                      'title': mediaItem.title,
                      'playable': mediaItem.playable,
                    })
                .toList();
            return rawMediaItems;
          }
          break;
        case 'onAudioFocusGained':
          if (onAudioFocusGained != null) onAudioFocusGained();
          break;
        case 'onAudioFocusLost':
          if (onAudioFocusLost != null) onAudioFocusLost();
          break;
        case 'onAudioFocusLostTransient':
          if (onAudioFocusLostTransient != null) onAudioFocusLostTransient();
          break;
        case 'onAudioFocusLostTransientCanDuck':
          if (onAudioFocusLostTransientCanDuck != null)
            onAudioFocusLostTransientCanDuck();
          break;
        case 'onAudioBecomingNoisy':
          if (onAudioBecomingNoisy != null) onAudioBecomingNoisy();
          break;
        case 'onClick':
          if (onClick != null) {
            final List args = call.arguments;
            MediaButton button = MediaButton.values[args[0]];
            onClick(button);
          }
          break;
        case 'onStop':
          onStop();
          break;
        case 'onPause':
          if (onPause != null) onPause();
          break;
        case 'onPrepare':
          if (onPrepare != null) onPrepare();
          break;
        case 'onPrepareFromMediaId':
          if (onPrepareFromMediaId != null) {
            final List args = call.arguments;
            String mediaId = args[0];
            onPrepareFromMediaId(mediaId);
          }
          break;
        case 'onPlay':
          if (onPlay != null) onPlay();
          break;
        case 'onPlayFromMediaId':
          if (onPlayFromMediaId != null) {
            final List args = call.arguments;
            String mediaId = args[0];
            onPlayFromMediaId(mediaId);
          }
          break;
        case 'onAddQueueItem':
          if (onAddQueueItem != null) {
            final List args = call.arguments;
            String mediaId = args[0];
            onAddQueueItem(mediaId);
          }
          break;
        case 'onAddQueueItemAt':
          if (onAddQueueItem != null) {
            final List args = call.arguments;
            String mediaId = args[0];
            int index = args[1];
            onAddQueueItemAt(mediaId, index);
          }
          break;
        case 'onRemoveQueueItem':
          if (onRemoveQueueItem != null) {
            final List args = call.arguments;
            String mediaId = args[0];
            onRemoveQueueItem(mediaId);
          }
          break;
        case 'onSkipToNext':
          if (onSkipToNext != null) onSkipToNext();
          break;
        case 'onSkipToPrevious':
          if (onSkipToPrevious != null) onSkipToPrevious();
          break;
        case 'onSkipToQueueItem':
          if (onSkipToQueueItem != null) {
            final List args = call.arguments;
            int id = args[0];
            onSkipToQueueItem(id);
          }
          break;
        case 'onSeekTo':
          if (onSeekTo != null) {
            final List args = call.arguments;
            int pos = args[0];
            onSeekTo(pos);
          }
          break;
        default:
          if (onCustomAction != null) {
            if (call.method.startsWith(_CUSTOM_PREFIX)) {
              onCustomAction(
                  call.method.substring(_CUSTOM_PREFIX.length), call.arguments);
            }
          }
          break;
      }
    });
    await onStart();
    await _backgroundChannel.invokeMethod('stopped');
    _backgroundChannel.setMethodCallHandler(null);
    _state = null;
  }

  /// Sets the current playback state and dictate which controls should be
  /// visible in the notification, Wear OS and Android Auto.
  ///
  /// All clients will be notified so they can update their display.
  static Future<void> setState(
      {@required List<MediaControl> controls,
      @required PlaybackState state,
      int position = 0,
      double speed = 1.0,
      int updateTime}) async {
    _state = state;
    List<Map> rawControls = controls
        .map((control) => {
              'androidIcon': control.androidIcon,
              'label': control.label,
              'action': control.action.index,
            })
        .toList();
    await _backgroundChannel.invokeMethod(
        'setState', [rawControls, state.index, position, speed, updateTime]);
  }

  /// Sets the current queue and notifies all clients.
  static Future<void> setQueue(List<MediaItem> queue) async {
    await _backgroundChannel.invokeMethod('setQueue', _mediaItems2raw(queue));
  }

  /// Sets the currently playing media item and notifies all clients.
  static Future<void> setMediaItem(MediaItem mediaItem) async {
    await _backgroundChannel.invokeMethod(
        'setMediaItem', _mediaItem2raw(mediaItem));
  }

  /// In Android, forces media button events to be routed to your active media
  /// session.
  /// 
  /// This is necessary if you want to play TextToSpeech in the background and
  /// still respond to media button events. You should call it just before
  /// playing TextToSpeech.
  ///
  /// This is not necessary if you are playing normal audio in the background
  /// such as music because this kind of "normal" audio playback will
  /// automatically qualify your app to receive media button events.
  static Future<void> androidForceEnableMediaButtons() async {
    await _backgroundChannel.invokeMethod('androidForceEnableMediaButtons');
  }
}
