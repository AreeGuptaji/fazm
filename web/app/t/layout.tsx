export default function GuideLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <div
      style={{
        overflow: "auto",
        height: "auto",
        background: "#ffffff",
        color: "#111827",
      }}
    >
      {children}
    </div>
  );
}
