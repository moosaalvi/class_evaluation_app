# Class Evaluation App

A CMS-like Flutter application for class/assessment evaluation.  
**Note:** All users (students and teachers) are pre-registered; there is no public signup.

## Features

- **Role-based Dashboard**
  - Students and teachers get personalized dashboards after login.
- **Profile Management**
  - Add/change profile picture (saved locally).
- **Subject List**
  - View all assigned subjects/courses.
- **Assessment/Evaluation**
  - Submit evaluations for students (marks/comments).
  - Offline mode: Save evaluations locally and auto-upload when online.
  - Edit submitted evaluations.
- **Progress Tracking**
  - See evaluation progress for each subject.
- **Network Awareness**
  - App automatically detects online/offline status.

## Result Feature (Coming Soon)

- **Individual Results**
  - Students can view their own evaluation results.
  - Evaluator roll numbers will be hidden for privacy.
- **Collective Results**
  - Teachers can view results for all students in a subject.
  - Teachers see which student evaluated whom and the marks/comments.
- **Privacy**
  - Students cannot see who evaluated them; only their own results are visible.

## Getting Started

1. **Clone the repository:**
   ```sh
   git clone https://github.com/yourusername/class_evaluation_app.git
   cd class_evaluation_app
   ```

2. **Install dependencies:**
   ```sh
   flutter pub get
   ```

3. **Run the app:**
   ```sh
   flutter run
   ```

## Screenshots

Coming Soon

## Tech Stack

- **Flutter** (UI)
- **GetX** (State management & navigation)
- **Shared Preferences** (Local storage)
- **HTTP** (API calls)
- **Connectivity Plus** (Network status)
- **Image Picker** (Profile images)

## Contributing

Pull requests are welcome! For major changes, please open an issue first to discuss what you would like to change.

## License

MIT License

---

**Note:**  
The result page and summary features will be added soon.  
Teachers will have full access to all student results, while students will only see their own evaluations with evaluator roll numbers hidden for privacy.
