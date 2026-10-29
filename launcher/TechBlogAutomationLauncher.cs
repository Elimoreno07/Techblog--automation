using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using System.Windows.Forms;

namespace TechBlogAutomationLauncher
{
    internal static class Program
    {
        [STAThread]
        private static void Main(string[] args)
        {
            if (args.Length > 0 && args[0] == "--self-test")
            {
                RunSelfTest();
                return;
            }

            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            Application.Run(new MainForm());
        }

        private static void RunSelfTest()
        {
            string root = AppDomain.CurrentDomain.BaseDirectory;
            string script = Path.Combine(root, "scripts", "New-TechBlogPost.ps1");
            string pwsh = PowerShellLocator.Find();
            bool ok = File.Exists(script) && !String.IsNullOrEmpty(pwsh);
            Console.WriteLine("ProjectRoot=" + root);
            Console.WriteLine("Script=" + (File.Exists(script) ? "OK" : "MISSING"));
            Console.WriteLine("PowerShell7=" + (String.IsNullOrEmpty(pwsh) ? "MISSING" : pwsh));
            Environment.ExitCode = ok ? 0 : 1;
        }
    }

    internal sealed class MainForm : Form
    {
        private readonly TextBox versionBox = new TextBox();
        private readonly TextBox dateBox = new TextBox();
        private readonly TextBox yearBox = new TextBox();
        private readonly TextBox basePostBox = new TextBox();
        private readonly TextBox siteUrlBox = new TextBox();
        private readonly TextBox listBox = new TextBox();
        private readonly TextBox clientIdBox = new TextBox();
        private readonly TextBox outputBox = new TextBox();
        private readonly Button previewButton = new Button();
        private readonly Button publishButton = new Button();
        private readonly Button installButton = new Button();
        private readonly Label statusLabel = new Label();
        private Process activeProcess;

        public MainForm()
        {
            Text = "TechBlog Automation";
            StartPosition = FormStartPosition.CenterScreen;
            MinimumSize = new Size(820, 690);
            Size = new Size(920, 760);
            Font = new Font("Segoe UI", 9F);
            Icon = SystemIcons.Application;

            TableLayoutPanel root = new TableLayoutPanel();
            root.Dock = DockStyle.Fill;
            root.Padding = new Padding(18);
            root.ColumnCount = 1;
            root.RowCount = 5;
            root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            root.RowStyles.Add(new RowStyle(SizeType.Percent, 100F));
            root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            Controls.Add(root);

            Label title = new Label();
            title.Text = "Crear post de TechBlog desde una plantilla";
            title.Font = new Font("Segoe UI Semibold", 16F);
            title.AutoSize = true;
            title.Margin = new Padding(0, 0, 0, 12);
            root.Controls.Add(title, 0, 0);

            TableLayoutPanel fields = BuildFields();
            root.Controls.Add(fields, 0, 1);

            FlowLayoutPanel actions = new FlowLayoutPanel();
            actions.AutoSize = true;
            actions.Dock = DockStyle.Fill;
            actions.FlowDirection = FlowDirection.LeftToRight;
            actions.Margin = new Padding(0, 12, 0, 8);

            previewButton.Text = "Crear vista previa";
            previewButton.AutoSize = true;
            previewButton.Padding = new Padding(10, 5, 10, 5);
            previewButton.Click += async delegate { await RunAutomationAsync(false); };

            publishButton.Text = "Publicar en SharePoint";
            publishButton.AutoSize = true;
            publishButton.Padding = new Padding(10, 5, 10, 5);
            publishButton.Click += async delegate { await RunAutomationAsync(true); };

            installButton.Text = "Instalar PnP.PowerShell";
            installButton.AutoSize = true;
            installButton.Padding = new Padding(10, 5, 10, 5);
            installButton.Click += async delegate { await InstallPnpAsync(); };

            actions.Controls.Add(previewButton);
            actions.Controls.Add(publishButton);
            actions.Controls.Add(installButton);
            root.Controls.Add(actions, 0, 2);

            outputBox.Multiline = true;
            outputBox.ReadOnly = true;
            outputBox.ScrollBars = ScrollBars.Both;
            outputBox.WordWrap = false;
            outputBox.Dock = DockStyle.Fill;
            outputBox.Font = new Font("Consolas", 9F);
            outputBox.BackColor = Color.FromArgb(25, 25, 25);
            outputBox.ForeColor = Color.Gainsboro;
            root.Controls.Add(outputBox, 0, 3);

            statusLabel.AutoSize = true;
            statusLabel.Text = GetStartupStatus();
            statusLabel.Margin = new Padding(0, 8, 0, 0);
            root.Controls.Add(statusLabel, 0, 4);
        }

        private TableLayoutPanel BuildFields()
        {
            TableLayoutPanel fields = new TableLayoutPanel();
            fields.Dock = DockStyle.Top;
            fields.AutoSize = true;
            fields.ColumnCount = 2;
            fields.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 190F));
            fields.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100F));

            dateBox.Text = DateTime.Today.ToString("dd/MM/yyyy");
            yearBox.Text = DateTime.Today.Year.ToString();
            listBox.Text = ValueOrDefault("TECHBLOG_LIST", "Posts");
            basePostBox.Text = Environment.GetEnvironmentVariable("TECHBLOG_BASE_POST_URL") ?? "";
            siteUrlBox.Text = Environment.GetEnvironmentVariable("TECHBLOG_SITE_URL") ?? "";
            clientIdBox.Text = Environment.GetEnvironmentVariable("ENTRAID_APP_ID") ?? "";

            AddField(fields, "Versión nueva *", versionBox,
                "Formato AAAA.NN.NNN, por ejemplo 2026.85.002");
            AddField(fields, "Fecha de publicación *", dateBox,
                "Formato dd/MM/yyyy");
            AddField(fields, "Año de documentación", yearBox,
                "Cuatro dígitos, por ejemplo 2026");
            AddField(fields, "URL o ID del post base *", basePostBox,
                "URL completa de Post.aspx?ID=... o solo el ID");
            AddField(fields, "URL del sitio", siteUrlBox,
                "Solo es necesaria si el post base se indica mediante un ID");
            AddField(fields, "Lista", listBox,
                "Normalmente Posts");
            AddField(fields, "Entra Application (client) ID *", clientIdBox,
                "Se usa solo durante esta ejecución y no se guarda");

            return fields;
        }

        private static void AddField(TableLayoutPanel panel, string labelText, Control input, string hint)
        {
            int row = panel.RowCount++;
            panel.RowStyles.Add(new RowStyle(SizeType.AutoSize));

            Label label = new Label();
            label.Text = labelText;
            label.AutoSize = true;
            label.Anchor = AnchorStyles.Left;
            label.Margin = new Padding(0, 7, 10, 7);

            input.Dock = DockStyle.Fill;
            input.Margin = new Padding(0, 4, 0, 1);

            ToolTip tip = new ToolTip();
            tip.SetToolTip(label, hint);
            tip.SetToolTip(input, hint);

            panel.Controls.Add(label, 0, row);
            panel.Controls.Add(input, 1, row);
        }

        private string GetStartupStatus()
        {
            string pwsh = PowerShellLocator.Find();
            if (String.IsNullOrEmpty(pwsh))
            {
                return "PowerShell 7 no encontrado. Instálalo antes de ejecutar la automatización.";
            }
            return "PowerShell 7 detectado: " + pwsh;
        }

        private bool ValidateInputs()
        {
            if (!Regex.IsMatch(versionBox.Text.Trim(), @"^\d{4}\.\d{2}\.\d{3}$"))
            {
                ShowValidation("La versión debe tener el formato AAAA.NN.NNN.", versionBox);
                return false;
            }

            DateTime parsedDate;
            if (!DateTime.TryParseExact(dateBox.Text.Trim(), "dd/MM/yyyy",
                System.Globalization.CultureInfo.InvariantCulture,
                System.Globalization.DateTimeStyles.None, out parsedDate))
            {
                ShowValidation("La fecha debe tener el formato dd/MM/yyyy.", dateBox);
                return false;
            }

            if (!String.IsNullOrWhiteSpace(yearBox.Text) && !Regex.IsMatch(yearBox.Text.Trim(), @"^\d{4}$"))
            {
                ShowValidation("El año debe contener cuatro dígitos.", yearBox);
                return false;
            }

            if (String.IsNullOrWhiteSpace(basePostBox.Text))
            {
                ShowValidation("Indica la URL o el ID del post base.", basePostBox);
                return false;
            }

            if (Regex.IsMatch(basePostBox.Text.Trim(), @"^\d+$") && String.IsNullOrWhiteSpace(siteUrlBox.Text))
            {
                ShowValidation("Si indicas solo el ID, debes informar la URL del sitio.", siteUrlBox);
                return false;
            }

            if (String.IsNullOrWhiteSpace(clientIdBox.Text))
            {
                ShowValidation("Indica el Application (client) ID autorizado por Microsoft Entra.", clientIdBox);
                return false;
            }

            Guid clientId;
            if (!Guid.TryParse(clientIdBox.Text.Trim(), out clientId))
            {
                ShowValidation("El Application (client) ID debe ser un GUID, no un usuario ni un correo.", clientIdBox);
                return false;
            }

            return true;
        }

        private void ShowValidation(string message, Control control)
        {
            MessageBox.Show(this, message, "Datos incompletos", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            control.Focus();
        }

        private async Task RunAutomationAsync(bool publish)
        {
            if (!ValidateInputs()) return;

            if (publish)
            {
                DialogResult answer = MessageBox.Show(this,
                    "Se creará un nuevo elemento en SharePoint. ¿Quieres continuar?",
                    "Confirmar publicación", MessageBoxButtons.YesNo, MessageBoxIcon.Warning,
                    MessageBoxDefaultButton.Button2);
                if (answer != DialogResult.Yes) return;
            }

            string root = AppDomain.CurrentDomain.BaseDirectory;
            string script = Path.Combine(root, "scripts", "New-TechBlogPost.ps1");
            if (!File.Exists(script))
            {
                MessageBox.Show(this,
                    "No se encuentra scripts\\New-TechBlogPost.ps1. Mantén el EXE en la carpeta raíz del proyecto.",
                    "Archivo no encontrado", MessageBoxButtons.OK, MessageBoxIcon.Error);
                return;
            }

            string pwsh = PowerShellLocator.Find();
            if (String.IsNullOrEmpty(pwsh))
            {
                MessageBox.Show(this,
                    "No se ha encontrado PowerShell 7.4 o posterior. Instálalo desde Microsoft y vuelve a abrir el programa.",
                    "PowerShell 7 requerido", MessageBoxButtons.OK, MessageBoxIcon.Error);
                return;
            }

            StringBuilder arguments = new StringBuilder();
            arguments.Append("-NoLogo -NoProfile -File ").Append(Quote(script));
            arguments.Append(" -Version ").Append(Quote(versionBox.Text.Trim()));
            arguments.Append(" -PublishDate ").Append(Quote(dateBox.Text.Trim()));
            if (!String.IsNullOrWhiteSpace(yearBox.Text))
                arguments.Append(" -DocumentationYear ").Append(Quote(yearBox.Text.Trim()));
            arguments.Append(" -BasePost ").Append(Quote(basePostBox.Text.Trim()));
            if (!String.IsNullOrWhiteSpace(siteUrlBox.Text))
                arguments.Append(" -SiteUrl ").Append(Quote(siteUrlBox.Text.Trim()));
            if (!String.IsNullOrWhiteSpace(listBox.Text))
                arguments.Append(" -ListName ").Append(Quote(listBox.Text.Trim()));
            if (publish) arguments.Append(" -Publish -Confirm:$false");

            ProcessStartInfo info = CreateProcessInfo(pwsh, arguments.ToString(), root);
            info.EnvironmentVariables["TECHBLOG_AUTH_MODE"] = "Interactive";
            info.EnvironmentVariables["ENTRAID_APP_ID"] = clientIdBox.Text.Trim();
            await RunProcessAsync(info, publish ? "Publicación" : "Vista previa");
        }

        private async Task InstallPnpAsync()
        {
            string pwsh = PowerShellLocator.Find();
            if (String.IsNullOrEmpty(pwsh))
            {
                MessageBox.Show(this, "No se encontró PowerShell 7.", "Requisito ausente",
                    MessageBoxButtons.OK, MessageBoxIcon.Error);
                return;
            }

            DialogResult answer = MessageBox.Show(this,
                "Se descargará PnP.PowerShell desde PowerShell Gallery para el usuario actual. ¿Continuar?",
                "Instalar dependencia", MessageBoxButtons.YesNo, MessageBoxIcon.Question);
            if (answer != DialogResult.Yes) return;

            string installer = Path.Combine(AppDomain.CurrentDomain.BaseDirectory,
                "scripts", "Install-PnPPowerShell.ps1");
            if (!File.Exists(installer))
            {
                MessageBox.Show(this, "No se encuentra scripts\\Install-PnPPowerShell.ps1.",
                    "Archivo no encontrado", MessageBoxButtons.OK, MessageBoxIcon.Error);
                return;
            }

            ProcessStartInfo info = CreateProcessInfo(pwsh,
                "-NoLogo -NoProfile -File " + Quote(installer), AppDomain.CurrentDomain.BaseDirectory);
            await RunProcessAsync(info, "Instalación de PnP.PowerShell");
        }

        private async Task RunProcessAsync(ProcessStartInfo info, string operation)
        {
            SetBusy(true);
            AppendOutput("\r\n=== " + operation + " ===\r\n");

            try
            {
                activeProcess = new Process();
                activeProcess.StartInfo = info;
                activeProcess.EnableRaisingEvents = true;
                activeProcess.OutputDataReceived += delegate(object sender, DataReceivedEventArgs e)
                {
                    if (e.Data != null) AppendOutput(e.Data + Environment.NewLine);
                };
                activeProcess.ErrorDataReceived += delegate(object sender, DataReceivedEventArgs e)
                {
                    if (e.Data != null) AppendOutput(e.Data + Environment.NewLine);
                };

                activeProcess.Start();
                activeProcess.BeginOutputReadLine();
                activeProcess.BeginErrorReadLine();
                await Task.Run(delegate { activeProcess.WaitForExit(); });
                int exitCode = activeProcess.ExitCode;

                AppendOutput("=== Código de salida: " + exitCode + " ===\r\n");
                if (exitCode == 0)
                {
                    MessageBox.Show(this, operation + " completada correctamente.", "Finalizado",
                        MessageBoxButtons.OK, MessageBoxIcon.Information);
                }
                else
                {
                    MessageBox.Show(this, operation + " terminó con errores. Revisa el registro de la ventana.",
                        "Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
                }
            }
            catch (Exception ex)
            {
                AppendOutput("ERROR: " + ex.Message + Environment.NewLine);
                MessageBox.Show(this, ex.Message, "No se pudo iniciar el proceso",
                    MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
            finally
            {
                if (activeProcess != null) activeProcess.Dispose();
                activeProcess = null;
                SetBusy(false);
            }
        }

        private static ProcessStartInfo CreateProcessInfo(string executable, string arguments, string workingDirectory)
        {
            ProcessStartInfo info = new ProcessStartInfo();
            info.FileName = executable;
            info.Arguments = arguments;
            info.WorkingDirectory = workingDirectory;
            info.UseShellExecute = false;
            info.CreateNoWindow = true;
            info.RedirectStandardOutput = true;
            info.RedirectStandardError = true;
            info.StandardOutputEncoding = Encoding.UTF8;
            info.StandardErrorEncoding = Encoding.UTF8;
            return info;
        }

        private void SetBusy(bool busy)
        {
            previewButton.Enabled = !busy;
            publishButton.Enabled = !busy;
            installButton.Enabled = !busy;
            UseWaitCursor = busy;
            statusLabel.Text = busy ? "Proceso en ejecución..." : GetStartupStatus();
        }

        private void AppendOutput(string value)
        {
            if (outputBox.InvokeRequired)
            {
                outputBox.BeginInvoke(new Action<string>(AppendOutput), value);
                return;
            }
            string plainText = Regex.Replace(value, "\\x1B\\[[0-?]*[ -/]*[@-~]", "");
            outputBox.AppendText(plainText);
        }

        private static string Quote(string value)
        {
            return "\"" + value.Replace("\"", "\\\"") + "\"";
        }

        private static string ValueOrDefault(string name, string fallback)
        {
            string value = Environment.GetEnvironmentVariable(name);
            return String.IsNullOrWhiteSpace(value) ? fallback : value;
        }
    }

    internal static class PowerShellLocator
    {
        public static string Find()
        {
            string configured = Environment.GetEnvironmentVariable("TECHBLOG_PWSH_PATH");
            if (!String.IsNullOrWhiteSpace(configured) && File.Exists(configured)) return configured;

            string baseDirectory = AppDomain.CurrentDomain.BaseDirectory;
            string userProfile = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
            string[] candidates = new string[]
            {
                Path.Combine(baseDirectory, "runtime", "pwsh.exe"),
                Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "PowerShell", "7", "pwsh.exe"),
                Path.Combine(userProfile, ".cache", "codex-runtimes", "codex-primary-runtime", "dependencies", "native", "powershell", "pwsh.exe")
            };

            foreach (string candidate in candidates)
            {
                if (File.Exists(candidate)) return candidate;
            }

            try
            {
                ProcessStartInfo info = new ProcessStartInfo("where.exe", "pwsh.exe");
                info.UseShellExecute = false;
                info.CreateNoWindow = true;
                info.RedirectStandardOutput = true;
                using (Process process = Process.Start(info))
                {
                    string result = process.StandardOutput.ReadLine();
                    process.WaitForExit();
                    if (!String.IsNullOrWhiteSpace(result) && File.Exists(result)) return result;
                }
            }
            catch { }

            return null;
        }
    }
}
