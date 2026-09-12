using System.Windows.Controls;
using System.Windows.Media;

namespace ConsoleMenu.Wpf.Views
{
    public partial class Ps4ShellView : ShellViewBase
    {
        public Ps4ShellView() { InitializeComponent(); }

        protected override string ThemeName => "ps4";

        protected override void UpdateHero()
        {
            base.UpdateHero();
            var list = Find<ListBox>("GamesList");
            var title = Find<TextBlock>("HeroTitle");
            if (list == null || title == null) return;
            var idx = list.SelectedIndex < 0 ? 0 : list.SelectedIndex;
            title.RenderTransform = new TranslateTransform(idx * 150.0 + 178.0, 0);
            if (list.SelectedItem != null) list.ScrollIntoView(list.SelectedItem);
        }
    }
}