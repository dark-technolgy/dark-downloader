import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:flutter/services.dart';
import 'dart:async';

import '../../config/localization.dart';
import '../../providers/locale_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class VideoPlayerScreen extends ConsumerStatefulWidget {
  final String source;
  final String title;

  const VideoPlayerScreen({
    required this.source,
    required this.title,
    super.key,
  });

  @override
  ConsumerState<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends ConsumerState<VideoPlayerScreen> {
  late final Player player = Player();
  late final VideoController controller = VideoController(player);
  
  bool _showControls = true;
  Timer? _controlsTimer;
  double _playbackSpeed = 1.0;
  bool _isLocked = false;

  @override
  void initState() {
    super.initState();
    player.open(Media(widget.source));
    
    // إخفاء شريط النظام وتغيير الاتجاه
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
      DeviceOrientation.portraitUp,
    ]);

    _startControlsTimer();
  }

  void _startControlsTimer() {
    _controlsTimer?.cancel();
    _controlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _showControls && player.state.playing) {
        setState(() => _showControls = false);
      }
    });
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
      if (_showControls) _startControlsTimer();
    });
  }

  @override
  void dispose() {
    _controlsTimer?.cancel();
    player.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    super.dispose();
  }

  Future<void> _setPlaybackSpeed(double speed) async {
    await player.setRate(speed);
    setState(() => _playbackSpeed = speed);
  }

  void _showTracksDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0A0A0A),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) {
        return DefaultTabController(
          length: 2,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const TabBar(
                indicatorColor: Color(0xFF00A3FF),
                tabs: [
                  Tab(text: "الصوت (Audio)"),
                  Tab(text: "الترجمة (Subtitles)"),
                ],
              ),
              Flexible(
                child: SizedBox(
                  height: 300,
                  child: TabBarView(
                    children: [
                      // Audio Tracks
                      ListView(
                        children: player.state.tracks.audio.map((track) {
                          return ListTile(
                            title: Text(track.title ?? track.language ?? "مسار صوتي", style: const TextStyle(color: Colors.white)),
                            subtitle: Text(track.codec ?? "", style: const TextStyle(color: Colors.grey, fontSize: 11)),
                            trailing: player.state.track.audio == track ? const Icon(Icons.check, color: Color(0xFF00A3FF)) : null,
                            onTap: () {
                              player.setAudioTrack(track);
                              Navigator.pop(context);
                            },
                          );
                        }).toList(),
                      ),
                      // Subtitles
                      ListView(
                        children: [
                          ListTile(
                            title: const Text("بدون ترجمة", style: TextStyle(color: Colors.white)),
                            onTap: () {
                              player.setSubtitleTrack(SubtitleTrack.no());
                              Navigator.pop(context);
                            },
                          ),
                          ...player.state.tracks.subtitle.map((track) {
                            return ListTile(
                              title: Text(track.title ?? track.language ?? "ترجمة", style: const TextStyle(color: Colors.white)),
                              trailing: player.state.track.subtitle == track ? const Icon(Icons.check, color: Color(0xFF00A3FF)) : null,
                              onTap: () {
                                player.setSubtitleTrack(track);
                                Navigator.pop(context);
                              },
                            );
                          }),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalization.translate;
    final locale = ref.watch(localeProvider);

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _toggleControls,
        onDoubleTapDown: (details) {
          final screenWidth = MediaQuery.of(context).size.width;
          if (details.globalPosition.dx < screenWidth / 2) {
            player.seek(player.state.position - const Duration(seconds: 10));
          } else {
            player.seek(player.state.position + const Duration(seconds: 10));
          }
        },
        child: Stack(
          children: [
            Center(
              child: Video(
                controller: controller,
                controls: NoVideoControls, // سنبني عناصر التحكم الخاصة بنا
              ),
            ),
            
            // عناصر التحكم
            AnimatedOpacity(
              opacity: _showControls ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 300),
              child: _showControls 
                ? _buildControlsOverlay(context, t, locale) 
                : const SizedBox.shrink(),
            ),

            // زر القفل
            if (_showControls)
              Positioned(
                left: 20,
                top: MediaQuery.of(context).size.height / 2 - 25,
                child: IconButton(
                  icon: Icon(
                    _isLocked ? Icons.lock_rounded : Icons.lock_open_rounded,
                    color: Colors.white,
                    size: 30,
                  ),
                  onPressed: () {
                    setState(() => _isLocked = !_isLocked);
                    _startControlsTimer();
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlsOverlay(BuildContext context, Function t, Locale locale) {
    if (_isLocked) {
      return Container(
        color: Colors.black26,
        child: const Center(child: Text("")), // زر القفل وحده يظهر
      );
    }

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black54, Colors.transparent, Colors.transparent, Colors.black54],
          stops: [0.0, 0.3, 0.7, 1.0],
        ),
      ),
      child: Column(
        children: [
          // شريط العلوي
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 20),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
                Expanded(
                  child: Text(
                    widget.title,
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.speed_rounded, color: Colors.white),
                  onPressed: _showSpeedDialog,
                ),
                IconButton(
                  icon: const Icon(Icons.picture_in_picture_alt_rounded, color: Colors.white),
                  onPressed: () {
                    // Note: PiP for media_kit on Windows/Android requires specific platform setup 
                    // which might not be fully linked in this VideoController version.
                    // Surfacing a generic error or ignoring if not supported.
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.settings_outlined, color: Colors.white),
                  onPressed: _showTracksDialog,
                ),
              ],
            ),
          ),
          
          const Spacer(),
          
          // أزرار التحكم في المنتصف
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                iconSize: 40,
                icon: const Icon(Icons.replay_10_rounded, color: Colors.white),
                onPressed: () => player.seek(player.state.position - const Duration(seconds: 10)),
              ),
              const SizedBox(width: 40),
              StreamBuilder<bool>(
                stream: player.stream.playing,
                builder: (context, snapshot) {
                  final playing = snapshot.data ?? false;
                  return IconButton(
                    iconSize: 70,
                    icon: Icon(
                      playing ? Icons.pause_circle_filled_rounded : Icons.play_circle_filled_rounded,
                      color: Colors.white,
                    ),
                    onPressed: () => player.playOrPause(),
                  );
                },
              ),
              const SizedBox(width: 40),
              IconButton(
                iconSize: 40,
                icon: const Icon(Icons.forward_10_rounded, color: Colors.white),
                onPressed: () => player.seek(player.state.position + const Duration(seconds: 10)),
              ),
            ],
          ),
          
          const Spacer(),
          
          // شريط التقدم والسفلي
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Column(
              children: [
                StreamBuilder<Duration>(
                  stream: player.stream.position,
                  builder: (context, snapshot) {
                    final position = snapshot.data ?? Duration.zero;
                    final duration = player.state.duration;
                    return Column(
                      children: [
                        SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 4,
                            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                            overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
                          ),
                          child: Slider(
                            value: position.inMilliseconds.toDouble(),
                            max: duration.inMilliseconds.toDouble().clamp(1.0, double.infinity),
                            activeColor: Theme.of(context).primaryColor,
                            inactiveColor: Colors.white24,
                            onChanged: (v) => player.seek(Duration(milliseconds: v.toInt())),
                          ),
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(_formatDuration(position), style: const TextStyle(color: Colors.white70, fontSize: 12)),
                            Text(_formatDuration(duration), style: const TextStyle(color: Colors.white70, fontSize: 12)),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showSpeedDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [0.5, 0.75, 1.0, 1.25, 1.5, 2.0].map((speed) {
              return ListTile(
                title: Text("${speed}x", style: const TextStyle(color: Colors.white)),
                trailing: _playbackSpeed == speed ? Icon(Icons.check, color: Theme.of(context).primaryColor) : null,
                onTap: () {
                  _setPlaybackSpeed(speed);
                  Navigator.pop(context);
                },
              );
            }).toList(),
          ),
        );
      },
    );
  }

  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(d.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(d.inSeconds.remainder(60));
    if (d.inHours > 0) return "${twoDigits(d.inHours)}:$twoDigitMinutes:$twoDigitSeconds";
    return "$twoDigitMinutes:$twoDigitSeconds";
  }
}
