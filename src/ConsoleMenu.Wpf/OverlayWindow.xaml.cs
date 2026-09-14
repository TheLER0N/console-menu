using System.Windows;
namespace ConsoleMenu.Wpf
{
public partial class OverlayWindow : Window
{
public OverlayWindow()
{
InitializeComponent();
}
private void OpenMain_Click(object sender, RoutedEventArgs e)
{
var mw = Application.Current.MainWindow as MainWindow;
if (mw != null) mw.ExitRestMode();
Hide();
}
private void Close_Click(object sender, RoutedEventArgs e)
{
Hide();
}
}
}