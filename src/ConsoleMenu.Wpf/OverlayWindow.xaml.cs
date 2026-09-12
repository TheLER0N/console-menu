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
            Application.Current.MainWindow?.Show();
            Application.Current.MainWindow?.Activate();
            Hide();
        }

        private void Close_Click(object sender, RoutedEventArgs e)
        {
            Hide();
        }
    }
}