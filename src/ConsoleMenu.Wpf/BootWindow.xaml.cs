using System;
using System.Windows;
using System.Windows.Media.Animation;
using System.Windows.Threading;
namespace ConsoleMenu.Wpf
{
    public partial class BootWindow : Window
    {
        public BootWindow()
        {
            InitializeComponent();
            Loaded += (s, e) =>
            {
                try { ((Storyboard)Resources["BootStory"]).Begin(this); }
                catch { }
                var timer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(3) };
                timer.Tick += (s2, e2) => { timer.Stop(); Close(); };
                timer.Start();
            };
        }
    }
}