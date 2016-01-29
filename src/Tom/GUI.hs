{-# LANGUAGE
NoImplicitPrelude
  #-}


module Tom.GUI
(
  runGUI,
  testMainWindow,
)
where


-- General
import BasePrelude hiding (on, try)
-- Lenses
import Lens.Micro.Platform hiding ((&), set)
-- GTK
import Graphics.UI.Gtk
-- Text
import qualified Data.Text as T
import Data.Text (Text)
-- IO
import Control.Monad.IO.Class
-- Time
import Data.Time
-- Parsing
import Text.Megaparsec
-- Tom-specific
import Tom.When
import Tom.Reminders
import Tom.Utils
import qualified Tom.RPC as RPC


-- todo: gray placeholders like “reminder text” and “when should it run”
  

runGUI :: IO ()
runGUI = do
  -- Initialise GTK.
  initGUI
  -- Create our GUI.
  (window, scheduleEntry, scheduleInfo, reminderEntry) <- createGUI
  -- Close the program when the window is closed.
  window `on` objectDestroy $ mainQuit
  -- When Enter is pressed in the schedule entry box, move focus to the
  -- reminder entry box.
  scheduleEntry `on` entryActivated $
    widgetGrabFocus reminderEntry
  --
  scheduleEntry `on` editableChanged $ do
    t <- get scheduleEntry entryText
    if T.null t
      then set scheduleInfo [labelText := "enter the schedule"]
      else case parseSchedule t of
             Left err -> set scheduleInfo [labelText := err]
             Right _  -> set scheduleInfo [labelText := "schedule is valid"]
  -- When Enter is pressed in the reminder entry box, schedule the reminder.
  reminderEntry `on` keyPressEvent $ tryEvent $ do
    "Return" <- T.unpack <$> eventKeyName
    [] <- eventModifier  -- so that Shift+Enter would work
    scheduleText <- liftIO $ get scheduleEntry entryText
    case parseSchedule scheduleText of
      Left _ -> return ()
      Right getSchedule -> liftIO $ do
        _schedule <- getSchedule
        _message <- do
          buffer <- get reminderEntry textViewBuffer
          get buffer textBufferText
        time <- getCurrentTime
        res <- RPC.call $ RPC.AddReminder $ Reminder {
          _schedule         = _schedule,
          _message          = _message,
          _created          = time,
          _lastSeen         = time,
          _lastAcknowledged = time,
          _snoozedUntil     = time }
        case res of
          Right _ -> widgetDestroy window
          Left err -> do
            d <- messageDialogNew
              (Just window)
              [DialogModal]
              MessageError
              ButtonsOk
              ("Error: " ++ RPC.showError err)
            dialogRun d
            widgetDestroy d
  -- Show the window and start GTK event loop.
  widgetShowAll window
  mainGUI

createGUI :: IO (Window, Entry, Label, TextView)
createGUI = do
  -- Create main window.
  window <- windowNew
  -- Set window's attributes:
  --   * amount of space around widgets contained in the window = 10
  --   * window must be centered
  --   * window's default size = 400×200
  set window [
    windowTitle := "Tom",
    containerBorderWidth := 10,
    windowGravity := GravityCenter,
    windowWindowPosition := WinPosCenter,
    windowDefaultWidth := 400,
    windowDefaultHeight := 200 ]
  -- Create a text box for entering schedule (“11pm” or something).
  scheduleEntry <- entryNew
  set scheduleEntry [
    widgetMarginBottom := 4 ]
  -- Create a label for showing information about entered schedule.
  scheduleInfo <- labelNew (Just "enter the schedule")
  set scheduleInfo [
    widgetMarginBottom := 6,
    miscXalign := 0,
    miscXpad := 1,
    labelEllipsize := EllipsizeEnd ]
  -- Create a text box for entering the reminder itself.
  reminderEntry <- textViewNew
  -- Text box's attributes:
  --   * there are left and right margins (otherwise it looks ugly)
  --   * text is wrapped by words, but if a word is too long, it will cause
  --     a scrollbar to appear (instead of getting broken in halves)
  --   * Tab isn't accepted as a character (so that the user could use it
  --     to switch back to scheduleEntry)
  set reminderEntry [
    textViewLeftMargin := 7,
    textViewRightMargin := 7,
    textViewWrapMode := WrapWord,
    textViewAcceptsTab := False ]
  -- Add top/bottom margins to reminderEntry. They have a *slightly*
  -- different color than the rest of the textbox, but I don't know of a
  -- better way to do this (e.g. adding padding with CSS doesn't work).
  widgetModifyBase reminderEntry StateActive (Color 30 30 30)
  textViewSetBorderWindowSize reminderEntry TextWindowTop 4
  textViewSetBorderWindowSize reminderEntry TextWindowBottom 4
  -- Create a ScrolledWindow containing reminderEntry, so that it would have
  -- scrollbars when there's too much text in it.
  reminderEntryScrolled <- scrolledWindowNew Nothing Nothing
  reminderEntryScrolled `containerAdd` reminderEntry
  -- Set attributes:
  --   * a nice border around reminderEntry
  --   * minimum size = 100×40
  set reminderEntryScrolled [
    scrolledWindowShadowType := ShadowEtchedIn,
    widgetWidthRequest := 100,
    widgetHeightRequest := 40 ]
  -- Create a layout (simply a table where widgets would be placed), put all
  -- other widgets there, and make the table a child of the main window.
  layout <- tableNew 2 1 False  -- 2 rows, 1 column, autostretching = off
  -- TODO: but shouldn't it be 3 rows?
  tableAttachDefaults layout scheduleEntry 0 1 0 1
  tableAttachDefaults layout scheduleInfo 0 1 1 2
  tableAttachDefaults layout reminderEntryScrolled 0 1 2 3
  window `containerAdd` layout
  -- Set layout's attributes:
  --   * amount of space between widgets = 10
  --   * scheduleEntry and scheduleInfo mustn't try to take more
  --     vertical space than needed
  set layout [
    tableChildYOptions scheduleEntry := [Fill],
    tableChildYOptions scheduleInfo := [Fill] ]
  return (window, scheduleEntry, scheduleInfo, reminderEntry)

parseSchedule :: Text -> Either String (IO When)
parseSchedule s = either (Left . show) Right $ parse scheduleP "" s
  where
    scheduleP = choice $ map (\p -> try (p <* eof)) allWhenParsers

testMainWindow :: IO ()
testMainWindow = testGUI (view _1 <$> createGUI)
