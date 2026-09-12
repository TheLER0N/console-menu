using System;
using System.Windows.Controls;
using System.Windows.Media;
using ConsoleMenu.Wpf.Services;

namespace ConsoleMenu.Wpf.Views
{
    public partial class Ps4ShellView : ShellViewBase
    {
        private const double Tile = 190.0;
        private const double Left = 24.0;
        private const double Gap = 28.0;

        public Ps4ShellView()
        {
            InitializeComponent();
            Loaded += (s, e) =>
            {
                var name = ShellDataService.ActiveProfile();
                BottomUserText.Text = name == null ? "User" : name.Name;
            };
        }

        protected override string ThemeName => "ps4";

        protected override void UpdateHero()
        {
            base.UpdateHero();
            var list = Find<ListBox>("GamesList");
            var title = Find<TextBlock>("HeroTitle");
            if (list == null || title == null) return;
            var idx = list.SelectedIndex < 0 ? 0 : list.SelectedIndex;
            title.RenderTransform = new System.Windows.Media.TranslateTransform(Left + idx * Tile + Tile + Gap, 0);
            if (list.SelectedItem != null) list.ScrollIntoView(list.SelectedItem);
        }
    }
}