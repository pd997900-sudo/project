import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';
import '../widgets/gradient_button.dart';
import 'role_selection_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  final List<Map<String, dynamic>> _slides = [
    {
      'icon': Icons.add_a_photo_rounded,
      'title': 'Report Road Damage Easily',
      'description': 'Capture photos, tag GPS locations, and report potholes, broken lights, and road hazards instantly.',
    },
    {
      'icon': Icons.timeline_rounded,
      'title': 'Track Complaints in Real Time',
      'description': 'Follow live progress updates, view repair stages, and inspect verified before & after repair photos.',
    },
    {
      'icon': Icons.handshake_rounded,
      'title': 'Build Safer Roads Together',
      'description': 'Connect citizens with active community repair teams and city maintenance crews for safer streets.',
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: AppTheme.gradientBackgroundDecoration,
        child: SafeArea(
          child: Column(
            children: [
              // Top Bar with Skip
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: const [
                        Icon(Icons.add_road_rounded, color: Colors.white, size: 24),
                        SizedBox(width: 8),
                        Text(
                          'RoadWatch',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    if (_currentPage < _slides.length - 1)
                      TextButton(
                        onPressed: () {
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(builder: (_) => const RoleSelectionScreen()),
                          );
                        },
                        child: const Text(
                          'Skip',
                          style: TextStyle(color: Colors.white70, fontSize: 16),
                        ),
                      ),
                  ],
                ),
              ),

              // Slide Content Carousel
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  onPageChanged: (index) {
                    setState(() {
                      _currentPage = index;
                    });
                  },
                  itemCount: _slides.length,
                  itemBuilder: (context, index) {
                    final slide = _slides[index];
                    return Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Glassmorphism Illustration Icon Holder
                          GlassCard(
                            borderRadius: 30,
                            padding: const EdgeInsets.all(36),
                            backgroundColor: Colors.white,
                            opacity: 0.2,
                            child: Icon(
                              slide['icon'] as IconData,
                              size: 100,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 40),

                          Text(
                            slide['title'] as String,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 26,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 16),

                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Text(
                              slide['description'] as String,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.8),
                                fontSize: 15,
                                height: 1.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),

              // Page Indicators & Action Button
              Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  children: [
                    // Dot Indicators
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(
                        _slides.length,
                        (index) => Container(
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          width: _currentPage == index ? 28 : 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: _currentPage == index
                                ? Colors.white
                                : Colors.white.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(5),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Next / Get Started Button
                    GradientButton(
                      text: _currentPage == _slides.length - 1 ? 'Get Started' : 'Next',
                      icon: Icons.arrow_forward_rounded,
                      onPressed: () {
                        if (_currentPage < _slides.length - 1) {
                          _pageController.nextPage(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeIn,
                          );
                        } else {
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(builder: (_) => const RoleSelectionScreen()),
                          );
                        }
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
