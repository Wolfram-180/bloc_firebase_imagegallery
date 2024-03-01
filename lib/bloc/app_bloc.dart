import 'dart:io';

import 'package:bloc/bloc.dart';
import 'package:bloc_firebase_gallery/auth/auth_error.dart';
import 'package:bloc_firebase_gallery/bloc/app_event.dart';
import 'package:bloc_firebase_gallery/bloc/app_state.dart';
import 'package:bloc_firebase_gallery/utils/upload_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

class AppBloc extends Bloc<AppEvent, AppState> {
  AppBloc()
      : super(
          const AppStateLoggedOut(
            isLoading: false,
          ),
        ) {
    //
    // handle
    // on<AppEvent>((event, emit) async {});
    //
    // handle go to registration event
    on<AppEventGoToRegistration>((event, emit) async {
      emit(
        const AppStateIsInRegistrationView(
          isLoading: false,
        ),
      );
    });
    //
    // handle log in event
    on<AppEventLogIn>((event, emit) async {
      emit(
        const AppStateLoggedOut(
          isLoading: true,
        ),
      );
      try {
        final email = event.email;
        final password = event.password;
        final userCredentials =
            await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
        final user = userCredentials.user!;
        final images = await _getImages(user.uid);
        emit(
          AppStateLoggedIn(
            isLoading: false,
            user: user,
            images: images,
          ),
        );
      } on FirebaseAuthException catch (e) {
        emit(
          AppStateLoggedOut(
            isLoading: false,
            authError: AuthError.from(e),
          ),
        );
      }
    });
    //
    // handle go to login event
    on<AppEventGoToLogin>((event, emit) {
      emit(
        const AppStateLoggedOut(
          isLoading: false,
        ),
      );
    });
    //
    // handle user registration
    on<AppEventRegister>((event, emit) async {
      emit(
        const AppStateIsInRegistrationView(
          isLoading: true,
        ),
      );
      final email = event.email;
      final password = event.password;
      try {
        // create the user
        final userCredentials =
            await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );
        emit(
          AppStateLoggedIn(
            isLoading: false,
            user: userCredentials.user!,
            images: const [],
          ),
        );
      } on FirebaseAuthException catch (e) {
        emit(
          AppStateIsInRegistrationView(
            isLoading: false,
            authError: AuthError.from(e),
          ),
        );
      }
    });
    //
    // handle app initializing
    on<AppEventInitialize>((event, emit) async {
      // get the current user
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        emit(
          const AppStateLoggedOut(
            isLoading: false,
          ),
        );
        return;
      } else {
        // user exists, get the images
        final images = await _getImages(user.uid);
        emit(
          AppStateLoggedIn(
            isLoading: false,
            user: user,
            images: images,
          ),
        );
      }
    });
    //
    // handle log out
    on<AppEventLogOut>((event, emit) async {
      // log the user out
      emit(
        const AppStateLoggedOut(
          isLoading: true,
        ),
      );
      await FirebaseAuth.instance.signOut();
      emit(
        const AppStateLoggedOut(
          isLoading: false,
        ),
      );
    });
    //
    // handle account deleting
    on<AppEventDeleteAccount>(
      (event, emit) async {
        final user = FirebaseAuth.instance.currentUser;
        //
        // log the user out if we dont have a current user
        if (user == null) {
          emit(
            const AppStateLoggedOut(
              isLoading: false,
            ),
          );
          return;
        }
        // start loading process
        emit(
          AppStateLoggedIn(
            isLoading: true,
            user: user,
            images: state.images ?? [],
          ),
        );
        // delete the user folder
        try {
          final folderContents =
              await FirebaseStorage.instance.ref(user.uid).listAll();
          for (final item in folderContents.items) {
            await item.delete().catchError((_) {}); // maybe handle, no need yet
          }
          // delete the folder itself
          await FirebaseStorage.instance
              .ref(user.uid)
              .delete()
              .catchError((_) {}); // maybe handle, no need yet
          // delete the user
          await user.delete();
          // log the user out
          await FirebaseAuth.instance.signOut();
          emit(
            const AppStateLoggedOut(
              isLoading: false,
            ),
          );
        } on FirebaseAuthException catch (e) {
          emit(
            AppStateLoggedIn(
              isLoading: false,
              user: user,
              images: state.images ?? [],
              authError: AuthError.from(e),
            ),
          );
        } on FirebaseException {
          // may be not possible to delete folder, so log out
          emit(
            const AppStateLoggedOut(
              isLoading: false,
            ),
          );
        }
      },
    );
    //
    // handle image upload
    on<AppEventUploadImage>(
      (event, emit) async {
        final user = state.user;
        // log out if no valid user
        if (user == null) {
          emit(
            const AppStateLoggedOut(
              isLoading: false,
            ),
          );
          return;
        }
        // start loading process
        emit(
          AppStateLoggedIn(
            isLoading: true,
            user: user,
            images: state.images ?? [],
          ),
        );
        // upload the file
        final file = File(event.filePathToUpload);
        await uploadImage(
          file: file,
          userId: user.uid,
        );
        // get the updated list of images
        final images = await _getImages(user.uid);
        // emit new images and stop loading
        emit(
          AppStateLoggedIn(
            isLoading: false,
            user: user,
            images: images,
          ),
        );
      },
    );
  }

  Future<Iterable<Reference>> _getImages(String userId) =>
      FirebaseStorage.instance.ref(userId).list().then(
            (listResult) => listResult.items,
          );
}
